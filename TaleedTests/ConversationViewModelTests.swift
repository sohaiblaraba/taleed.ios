import Foundation
@testable import Taleed
import Testing
import UIKit

// MARK: - Fakes

@MainActor
final class FakeMessagesApi: MessagesApi {
    var inboxPages: [Result<Page<InboxConversation>, Taleed.ApiError>] = []
    var conversation: Result<ConversationDetail, Taleed.ApiError> = .success(.fixture())
    var messagePages: [Result<Page<ChatMessage>, Taleed.ApiError>] = []
    var sendResults: [Result<ChatMessage, Taleed.ApiError>] = []
    var counts = UnreadCounts(messages: 1, notifications: 4)
    private(set) var conversationCalls = 0
    private(set) var messageCursors: [String?] = []
    private(set) var sent: [MessageDraft] = []
    private(set) var readCalls = 0
    private(set) var inboxCalls: [Bool] = []

    func conversations(cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> Page<InboxConversation> {
        inboxCalls.append(automatic)
        if !inboxPages.isEmpty { return try inboxPages.removeFirst().get() }
        return Page(items: [], nextCursor: nil, total: 0)
    }

    func conversation(id: String, automatic: Bool) async throws(Taleed.ApiError) -> ConversationDetail {
        conversationCalls += 1
        return try conversation.get()
    }

    func messages(conversationId: String, cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> Page<ChatMessage> {
        messageCursors.append(cursor)
        if !messagePages.isEmpty { return try messagePages.removeFirst().get() }
        return Page(items: [], nextCursor: nil, total: 0)
    }

    func sendMessage(conversationId: String, draft: MessageDraft) async throws(Taleed.ApiError) -> ChatMessage {
        sent.append(draft)
        if !sendResults.isEmpty { return try sendResults.removeFirst().get() }
        return .fixture("posted-\(sent.count)", isMine: true, at: 100, text: draft.text, clientId: draft.clientId)
    }

    func markRead(conversationId: String) async throws(Taleed.ApiError) -> UnreadCounts {
        readCalls += 1
        return counts
    }
}

/// A live stream the test feeds by hand.
@MainActor
final class FakeEventsSource: ConversationEventsSource {
    private(set) var afterIds: [String?] = []
    var continuation: AsyncThrowingStream<ConversationEvent, Error>.Continuation?

    func events(conversationId: String, after newestMessageId: String?) -> AsyncThrowingStream<ConversationEvent, Error> {
        afterIds.append(newestMessageId)
        let (stream, continuation) = AsyncThrowingStream<ConversationEvent, Error>.makeStream()
        self.continuation = continuation
        return stream
    }
}

// MARK: - Conversation view model

@MainActor
struct ConversationViewModelTests {
    let api = FakeMessagesApi()
    let events = FakeEventsSource()
    let members = FakeMembersApi()

    private func model(uploads: @escaping (Data) async throws(Taleed.ApiError) -> UploadedPhoto = { _ throws(Taleed.ApiError) in
        UploadedPhoto(key: "messages/k.webp", url: nil, thumbURL: nil)
    }) -> ConversationViewModel {
        var ids = 0
        return ConversationViewModel(conversationId: "c1", api: api, events: events, members: members, upload: uploads,
                                     now: { chatNow.addingTimeInterval(50) },
                                     makeClientId: {
                                         ids += 1
                                         return "client-\(ids)"
                                     })
    }

    @Test func loadsTheConversationAndMarksItReadOnceVisible() async {
        api.messagePages = [.success(Page(items: [.fixture("m2", at: 10), .fixture("m1")], nextCursor: "older", total: 3))]
        let model = model()
        var counts: UnreadCounts?
        model.onRead = { counts = $0 }
        await model.load()
        #expect(model.conversation?.id == "c1")
        #expect(model.messages.map(\.id) == ["m2", "m1"])
        #expect(model.hasOlder)
        #expect(api.readCalls == 0)
        await model.setVisible(true)
        #expect(api.readCalls == 1)
        #expect(counts == UnreadCounts(messages: 1, notifications: 4))
    }

    @Test func aFailedLoadShowsTheError() async {
        api.conversation = .failure(.network)
        let model = model()
        await model.load()
        #expect(model.loadError == .network)
        #expect(model.conversation == nil)
    }

    @Test func olderPagesMergeWithoutDuplicates() async {
        api.messagePages = [.success(Page(items: [.fixture("m3", at: 20), .fixture("m2", at: 10)], nextCursor: "p2", total: 3)),
                            .success(Page(items: [.fixture("m2", at: 10), .fixture("m1")], nextCursor: nil, total: 3))]
        let model = model()
        await model.load()
        await model.loadOlder()
        #expect(model.messages.map(\.id) == ["m3", "m2", "m1"])
        #expect(api.messageCursors == [nil, "p2"])
        #expect(!model.hasOlder)
    }

    @Test func sendingShowsTheBubbleThenTheMessage() async {
        let model = model()
        await model.load()
        model.text = "  Bonjour  "
        #expect(model.canSend)
        await model.send()
        #expect(api.sent == [MessageDraft(clientId: "client-1", text: "Bonjour", photoKey: nil)])
        #expect(model.outgoing.isEmpty)
        #expect(model.messages.first?.clientId == "client-1")
        #expect(model.text.isEmpty)
    }

    @Test func aLostAnswerKeepsTheBubbleAndRetriesWithTheSameClientId() async {
        api.sendResults = [.failure(.network)]
        let model = model()
        await model.load()
        model.text = "Bonjour"
        await model.send()
        #expect(model.outgoing.map(\.state) == [.failed])
        await model.retry("client-1")
        #expect(api.sent.map(\.clientId) == ["client-1", "client-1"])
        #expect(model.outgoing.isEmpty)
        #expect(model.messages.count == 1)
    }

    @Test func theStreamConfirmsABubbleByItsClientId() async {
        api.sendResults = [.failure(.network)]
        let model = model()
        await model.load()
        model.text = "Bonjour"
        await model.send()
        await model.receive(.fixture("posted", isMine: true, at: 60, clientId: "client-1"))
        #expect(model.outgoing.isEmpty)
        #expect(model.messages.map(\.id) == ["posted"])
    }

    @Test func aBlockDropsTheBubbleAndReloads() async {
        api.sendResults = [.failure(.failed(ApiFailure(status: 403, code: .blocked)))]
        let model = model()
        await model.load()
        api.conversation = .success(.fixture(canReply: false, replyBlock: .blocked, isBlocked: false))
        model.text = "Bonjour"
        await model.send()
        #expect(model.outgoing.isEmpty)
        #expect(model.notice == .error(.failed(ApiFailure(status: 403, code: .blocked))))
        await model.reloadConversation(automatic: false)
        #expect(model.conversation?.canReply == false)
    }

    @Test func aRefusedTextComesBackToTheComposer() async {
        api.sendResults = [.failure(.failed(ApiFailure(status: 400, code: .invalidRequest)))]
        let model = model()
        await model.load()
        model.text = "Bonjour"
        await model.send()
        #expect(model.outgoing.isEmpty)
        #expect(model.text == "Bonjour")
    }

    @Test func anIncomingMessageWhileVisibleMarksItRead() async {
        let model = model()
        await model.load()
        await model.setVisible(true)
        await model.receive(.fixture("new", at: 30))
        #expect(api.readCalls == 2)
        // The same message again (the stream can repeat one): merged, not read again.
        await model.receive(.fixture("new", at: 30))
        #expect(api.readCalls == 2)
        #expect(model.messages.map(\.id) == ["new"])
        // The member's own message from another device: no read mark.
        await model.receive(.fixture("mine", isMine: true, at: 40))
        #expect(api.readCalls == 2)
    }

    @Test func anOfferUpdateRefreshesEveryCardAndTheConversation() async {
        let pending = ChatOffer.fixture(status: .pending)
        api.messagePages = [.success(Page(items: [.fixture("offer", kind: .offer, offer: pending)], nextCursor: nil, total: 1))]
        let model = model()
        await model.load()
        let calls = api.conversationCalls
        let accepted = ChatOffer.fixture(status: .accepted)
        await model.receive(.fixture("update", kind: .offerUpdate, at: 40, text: "Acceptée", offer: accepted))
        let card = model.messages.first { $0.id == "offer" }
        #expect(card.flatMap(model.offer(in:))?.status == .accepted)
        #expect(api.conversationCalls == calls + 1)
    }

    /// The phone's clock a day ahead of the server's: an answer received after the conversation loaded
    /// still wins over its `pendingOffer` (never device time against server time).
    @Test func anOfferAnsweredAfterLoadingWinsWhateverThePhonesClock() async {
        let pending = ChatOffer.fixture(status: .pending)
        api.conversation = .success(.fixture(pendingOffer: pending))
        api.messagePages = [.success(Page(items: [.fixture("offer", kind: .offer, offer: pending)], nextCursor: nil, total: 1))]
        let model = ConversationViewModel(conversationId: "c1", api: api, events: events, members: members,
                                          upload: { _ throws(Taleed.ApiError) in UploadedPhoto(key: "k", url: nil, thumbURL: nil) },
                                          now: { chatNow.addingTimeInterval(86_400) })
        await model.load()
        let card = model.messages.first { $0.id == "offer" }
        #expect(card.flatMap(model.offer(in:))?.status == .pending)

        // The seller declines: the conversation no longer lists the offer as pending.
        api.conversation = .success(.fixture())
        await model.receive(.fixture("update", kind: .offerUpdate, at: 40, text: "Refusée", offer: .fixture(status: .declined)))
        #expect(card.flatMap(model.offer(in:))?.status == .declined)
        await model.reloadConversation(automatic: true)
        #expect(card.flatMap(model.offer(in:))?.status == .declined)
    }

    /// A conversation loaded after the last message about an offer gives its state now.
    @Test func aLaterConversationLoadWinsOverOlderMessages() async {
        let pending = ChatOffer.fixture(status: .pending)
        api.messagePages = [.success(Page(items: [.fixture("offer", kind: .offer, at: 10, offer: pending)], nextCursor: nil, total: 1))]
        let model = model()
        await model.load()
        let changed = ChatOffer(id: "o1", amount: 2500, status: .pending, expiresAt: chatNow.addingTimeInterval(60), createdAt: chatNow,
                                senderId: "other", isMine: false, sentBy: .seller, listingId: "l1", bundle: nil, canAccept: true,
                                canDecline: true, canCounter: true, canCancel: false, canPay: false, counterRange: nil)
        api.conversation = .success(.fixture(pendingOffer: changed))
        await model.reloadConversation(automatic: true)
        let card = model.messages.first { $0.id == "offer" }
        #expect(card.flatMap(model.offer(in:))?.canAccept == true)
    }

    @Test func theStreamStartsAfterTheNewestMessageAndRetriesFailedSends() async {
        api.messagePages = [.success(Page(items: [.fixture("m9", at: 10)], nextCursor: nil, total: 1))]
        api.sendResults = [.failure(.network)]
        let model = model()
        await model.load()
        model.text = "Bonjour"
        await model.send()
        let following = Task { await model.followLiveUpdates() }
        await waitUntil { events.continuation != nil }
        #expect(events.afterIds == ["m9"])
        events.continuation?.yield(.connected)
        await waitUntil { model.outgoing.isEmpty }
        events.continuation?.finish()
        await following.value
        #expect(api.sent.map(\.clientId) == ["client-1", "client-1"])
    }

    @Test func aGoneConversationShowsNotFound() async {
        let model = model()
        await model.load()
        let following = Task { await model.followLiveUpdates() }
        await waitUntil { events.continuation != nil }
        events.continuation?.finish(throwing: Taleed.ApiError.failed(ApiFailure(status: 404, code: .notFound)))
        await following.value
        #expect(model.loadError?.isNotFound == true)
    }

    @Test func aPhotoUploadsOnPickAndGoesWithTheMessage() async throws {
        let model = model()
        await model.load()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
        let data = try #require(image.pngData())
        await model.attachPhoto(data)
        #expect(model.photo?.key == "messages/k.webp")
        #expect(model.canSend)
        await model.send()
        #expect(api.sent.first?.photoKey == "messages/k.webp")
        #expect(api.sent.first?.text == nil)
        #expect(model.photo == nil)
    }

    @Test func aFailedUploadRemovesThePhoto() async throws {
        let model = model(uploads: { _ throws(Taleed.ApiError) in throw .failed(ApiFailure(status: 413, code: .fileTooLarge)) })
        await model.load()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
        await model.attachPhoto(try #require(image.pngData()))
        #expect(model.photo == nil)
        #expect(model.notice == .error(.failed(ApiFailure(status: 413, code: .fileTooLarge))))
    }

    @Test func blockingReloadsTheConversation() async {
        let model = model()
        await model.load()
        api.conversation = .success(.fixture(canReply: false, replyBlock: .blocked, isBlocked: true))
        await model.setBlocked(true)
        #expect(members.blockCalls == [true])
        #expect(model.conversation?.isBlocked == true)
        #expect(model.notice == .blocked(handle: "@lina_kh"))
    }
}

// MARK: - Inbox

@MainActor
struct InboxViewModelTests {
    let api = FakeMessagesApi()

    private func row(_ id: String, unread: Int = 0) -> InboxConversation {
        InboxConversation(id: id, role: .buyer, counterpart: .fixture(), listing: .fixture(), isOfficial: false,
                          lastMessage: ChatPreview(text: "Bonjour", isMine: false, createdAt: chatNow), unreadCount: unread,
                          lastMessageAt: chatNow)
    }

    @Test func readingAConversationClearsItsCounter() async {
        api.inboxPages = [.success(Page(items: [row("a", unread: 3), row("b")], nextCursor: nil, total: 2))]
        let model = InboxViewModel(api: api)
        await model.list.loadIfNeeded()
        model.markRead(conversationId: "a")
        #expect(model.list.items.first?.unreadCount == 0)
    }

    /// Back from a conversation within the reload's 2 s: the read mark clears the row, once.
    @Test func aReadMarkClearsTheRowOnce() async throws {
        api.inboxPages = [.success(Page(items: [row("a", unread: 3), row("b", unread: 1)], nextCursor: nil, total: 2))]
        let model = InboxViewModel(api: api)
        let reads = ConversationReads()
        await model.list.loadIfNeeded()
        reads.didRead(conversationId: "a")
        let mark = try #require(reads.latest)
        model.apply(mark)
        #expect(model.list.items.map(\.unreadCount) == [0, 1])
        // News in "a" since: the same mark applied again leaves it bold.
        model.list.update(row("a", unread: 2))
        model.apply(mark)
        #expect(model.list.items.first?.unreadCount == 2)
        await model.reloadQuietly()
        #expect(api.inboxCalls == [false])
    }

    @Test func aQuietReloadIsAutomaticAndNotTooOften() async {
        api.inboxPages = [.success(Page(items: [row("a")], nextCursor: nil, total: 1)),
                          .success(Page(items: [row("b"), row("a")], nextCursor: nil, total: 2))]
        let model = InboxViewModel(api: api)
        await model.list.loadIfNeeded()
        await model.reloadQuietly()
        #expect(api.inboxCalls == [false])
        await model.reloadQuietly(now: .now + .seconds(3))
        #expect(api.inboxCalls == [false, true])
        #expect(model.list.items.map(\.id) == ["b", "a"])
    }

    @Test func theFilterKeepsTheLoadedRows() async {
        var seller = row("s")
        seller = InboxConversation(id: "s", role: .seller, counterpart: seller.counterpart, listing: seller.listing, isOfficial: false,
                                   lastMessage: nil, unreadCount: 0, lastMessageAt: chatNow)
        api.inboxPages = [.success(Page(items: [row("a"), seller], nextCursor: nil, total: 2))]
        let model = InboxViewModel(api: api)
        await model.list.loadIfNeeded()
        model.filter = .selling
        #expect(model.visibleItems.map(\.id) == ["s"])
        model.filter = .buying
        #expect(model.visibleItems.map(\.id) == ["a"])
    }
}
