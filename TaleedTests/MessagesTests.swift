import Foundation
@testable import Taleed
import TaleedAPI
import Testing
import UIKit

// MARK: - Fixtures

let chatNow = Date(timeIntervalSince1970: 1_790_000_000)

extension ChatMember {
    static func fixture(username: String? = "lina_kh", isOfficial: Bool = false) -> ChatMember {
        ChatMember(id: "m-\(username ?? "old")", username: username, displayName: username.map { "@\($0)" } ?? "Lina K.",
                   avatarURL: nil, isVerified: true, isOfficial: isOfficial)
    }
}

extension ConversationDetail {
    static func fixture(id: String = "c1", counterpart: ChatMember? = .fixture(), listing: ChatListing? = .fixture(),
                        isOfficial: Bool = false, canReply: Bool = true, replyBlock: ReplyBlock? = nil, isBlocked: Bool = false,
                        pendingOffer: ChatOffer? = nil) -> ConversationDetail {
        ConversationDetail(id: id, role: .buyer, counterpart: counterpart, listing: listing, isOfficial: isOfficial, unreadCount: 2,
                           canReply: canReply, replyBlock: replyBlock, isBlocked: isBlocked, offerRange: nil,
                           pendingOffer: pendingOffer)
    }
}

extension ChatListing {
    static func fixture(status: ChatListingStatus = .active) -> ChatListing {
        ChatListing(id: "l1", title: "Veste test", price: 3000, imageURL: nil, status: status)
    }
}

extension ChatOffer {
    static func fixture(id: String = "o1", status: ChatOfferStatus = .pending, expiresAt: Date = chatNow.addingTimeInterval(3600),
                        sentBy: ChatRole = .buyer, bundle: ChatBundle? = nil) -> ChatOffer {
        ChatOffer(id: id, amount: 2500, status: status, expiresAt: expiresAt, createdAt: chatNow, senderId: "me", isMine: true,
                  sentBy: sentBy, listingId: "l1", bundle: bundle, canAccept: false, canDecline: false, canCounter: false,
                  canCancel: status == .pending, canPay: false, counterRange: nil)
    }
}

extension ChatMessage {
    static func fixture(_ id: String, kind: ChatMessageKind = .text, isMine: Bool = false, at seconds: TimeInterval = 0,
                        text: String? = "Bonjour", clientId: String? = nil, offer: ChatOffer? = nil) -> ChatMessage {
        ChatMessage(id: id, kind: kind, senderId: isMine ? "me" : "other", isMine: isMine,
                    createdAt: chatNow.addingTimeInterval(seconds), clientId: clientId, text: text, html: nil, photoURL: nil,
                    callToAction: nil, offer: offer, offerEvent: nil, bundle: nil, order: nil)
    }
}

// MARK: - Server-sent events

struct ServerEventParserTests {
    @Test func cutsEventsAcrossChunksAndSkipsHeartbeats() {
        var parser = ServerEventParser()
        #expect(parser.feed(Data("retry: 3000\n\n: ping\n\nid: m1\nevent: mess".utf8)).isEmpty)
        let events = parser.feed(Data("age\ndata: {\"id\":\"m1\"}\n\n".utf8))
        #expect(events == [ServerEvent(id: "m1", event: "message", data: "{\"id\":\"m1\"}")])
        #expect(parser.retryMilliseconds == 3000)
    }

    @Test func joinsDataLinesAndReadsCarriageReturns() {
        var parser = ServerEventParser()
        let events = parser.feed(Data("data: a\r\ndata: b\r\n\r\nevent: other\ndata:c\n\n".utf8))
        #expect(events == [ServerEvent(id: nil, event: "message", data: "a\nb"), ServerEvent(id: nil, event: "other", data: "c")])
    }

    @MainActor
    @Test func onlyNetworkServerAndRateLimitReconnect() {
        let usual = Duration.seconds(3)
        #expect(GeneratedTaleedApi.reconnectDelay(after: .network, usual: usual) == usual)
        #expect(GeneratedTaleedApi.reconnectDelay(after: .server(status: 502), usual: usual) == usual)
        #expect(GeneratedTaleedApi.reconnectDelay(after: .rateLimited(retryAfter: 90), usual: usual) == .seconds(90))
        #expect(GeneratedTaleedApi.reconnectDelay(after: .rateLimited(retryAfter: nil), usual: usual) == .seconds(30))
        #expect(GeneratedTaleedApi.reconnectDelay(after: .unauthorized, usual: usual) == nil)
        #expect(GeneratedTaleedApi.reconnectDelay(after: .failed(ApiFailure(status: 404, code: .notFound)), usual: usual) == nil)
        #expect(GeneratedTaleedApi.reconnectDelay(after: .failed(ApiFailure(status: 403, code: .forbidden)), usual: usual) == nil)
    }

    @Test func theRequestResumesAfterTheNewestMessage() throws {
        let configuration = TaleedAPIAPIConfiguration(basePath: "http://localhost:3000/api/v1",
                                                      customHeaders: ["Authorization": "Bearer t", "Accept-Language": "ar"],
                                                      requestBuilderFactory: TaleedRequestBuilderFactory())
        let request = GeneratedTaleedApi.eventsRequest(conversationId: "c1", after: "m9", configuration: configuration)
        #expect(request.url?.absoluteString == "http://localhost:3000/api/v1/conversations/c1/events")
        #expect(request.value(forHTTPHeaderField: "Last-Event-ID") == "m9")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "ar")
    }
}

// MARK: - Copy and rules

struct ChatTextTests {
    @Test func listingBadgeOnlyWhenNotForSale() {
        #expect(ChatText.listingStatusKey(.active) == nil)
        #expect(ChatText.listingStatusKey(.reserved) == .listingStatusReserved)
        #expect(ChatText.listingStatusKey(.sold) == .listingStatusSold)
        #expect(ChatText.listingStatusKey(.hidden) == .bundleUnavailable)
        #expect(ChatText.listingStatusKey(.removed) == .bundleUnavailable)
        #expect(ChatText.listingStatusKey(.unknown) == .bundleUnavailable)
    }

    @Test func offerStatusAndEyebrow() {
        #expect(ChatText.offerStatusKey(.unknown) == .appOfferStatusClosed)
        #expect(ChatText.offerStatusKey(.countered) == .offersStatusCountered)
        #expect(ChatText.offerEyebrow(.fixture(sentBy: .buyer)) == .buyer)
        #expect(ChatText.offerEyebrow(.fixture(sentBy: .seller)) == .seller)
        let bundle = ChatBundle(id: "b1", items: [ChatBundleItem(listingId: "a", title: "A", price: 1, imageURL: nil),
                                                  ChatBundleItem(listingId: "b", title: "B", price: 2, imageURL: nil)], itemsTotal: 3)
        #expect(ChatText.offerEyebrow(.fixture(bundle: bundle)) == .bundle(count: 2))
    }

    @Test func aPendingOfferShowsExpiredOnceItsTimePassed() {
        let offer = ChatOffer.fixture(expiresAt: chatNow)
        #expect(offer.displayStatus(at: chatNow.addingTimeInterval(-1)) == .pending)
        #expect(offer.displayStatus(at: chatNow) == .expired)
        #expect(ChatOffer.fixture(status: .accepted, expiresAt: chatNow).displayStatus(at: chatNow.addingTimeInterval(60)) == .accepted)
    }

    @Test func readOnlyNoticeFollowsTheReason() {
        #expect(ChatText.readOnlyNotice(for: .fixture()) == nil)
        #expect(ChatText.readOnlyNotice(for: .fixture(isOfficial: true, canReply: false, replyBlock: .official)) == .official)
        #expect(ChatText.readOnlyNotice(for: .fixture(canReply: false, replyBlock: .blocked, isBlocked: true))
            == .youBlocked(handle: "@lina_kh"))
        // The blocked member reads the neutral text, never "you were blocked".
        #expect(ChatText.readOnlyNotice(for: .fixture(canReply: false, replyBlock: .blocked, isBlocked: false)) == .blocked)
        #expect(ChatText.readOnlyNotice(for: .fixture(counterpart: nil, canReply: false, replyBlock: .memberDeleted)) == .memberDeleted)
        #expect(ChatText.readOnlyNotice(for: .fixture(canReply: false, replyBlock: .unknown)) == .generic)
        #expect(ChatText.readOnlyNotice(for: .fixture(canReply: false, replyBlock: nil)) == .generic)
    }

    @Test func textIsTrimmedAndCappedAt2000() {
        #expect(ChatText.sendableText("  \n ") == nil)
        #expect(ChatText.sendableText("  Bonjour \n") == "Bonjour")
        let long = String(repeating: "a", count: 2100)
        #expect(ChatText.limited(long).count == 2000)
        // Counted in UTF-16 as the API: an emoji takes two.
        let emojis = String(repeating: "😀", count: 1001)
        #expect(ChatText.limited(emojis).utf16.count == 2000)
    }

    @Test func sendNeedsRepliesTextOrAnUploadedPhoto() {
        let uploading = ComposerPhoto(id: UUID(), preview: UIImage(), key: nil)
        let ready = ComposerPhoto(id: UUID(), preview: UIImage(), key: "messages/2026/10/0123456789abcdef.webp")
        #expect(!ComposerPhoto.canSend(canReply: true, text: " ", photo: nil))
        #expect(ComposerPhoto.canSend(canReply: true, text: "Salut", photo: nil))
        #expect(!ComposerPhoto.canSend(canReply: true, text: "Salut", photo: uploading))
        #expect(ComposerPhoto.canSend(canReply: true, text: "", photo: ready))
        #expect(!ComposerPhoto.canSend(canReply: false, text: "Salut", photo: ready))
    }

    @Test func sendFailuresKeepOrDropTheBubble() {
        #expect(ChatSendFailure(.network) == .keep)
        #expect(ChatSendFailure(.server(status: 503)) == .keep)
        #expect(ChatSendFailure(.rateLimited(retryAfter: 30)) == .keep)
        #expect(ChatSendFailure(.unauthorized) == .drop)
        #expect(ChatSendFailure(.failed(ApiFailure(status: 403, code: .blocked))) == .dropAndReload)
        #expect(ChatSendFailure(.failed(ApiFailure(status: 403, code: .conversationReadOnly))) == .dropAndReload)
        #expect(ChatSendFailure(.failed(ApiFailure(status: 404, code: .notFound))) == .dropAndReload)
        #expect(ChatSendFailure(.failed(ApiFailure(status: 400, code: .invalidRequest))) == .dropAndRestoreText)
    }

    @Test func menuFollowsTheConversation() {
        #expect(ConversationMenuActions(.fixture())
            == ConversationMenuActions(report: true, block: true, unblock: false, viewListing: true, viewProfile: true))
        #expect(ConversationMenuActions(.fixture(isBlocked: true))
            == ConversationMenuActions(report: true, block: false, unblock: true, viewListing: true, viewProfile: true))
        // The official thread: no report, no block, no listing.
        #expect(ConversationMenuActions(.fixture(counterpart: .fixture(username: "taleed", isOfficial: true), listing: nil,
                                                 isOfficial: true))
            == ConversationMenuActions(report: false, block: false, unblock: false, viewListing: false, viewProfile: true))
        // A deleted member: nothing to block or open.
        #expect(ConversationMenuActions(.fixture(counterpart: nil))
            == ConversationMenuActions(report: true, block: false, unblock: false, viewListing: true, viewProfile: false))
    }

    @Test func inboxFilterKeepsTheMembersSide() {
        func row(_ role: ChatRole, official: Bool = false) -> InboxConversation {
            InboxConversation(id: UUID().uuidString, role: role, counterpart: .fixture(), listing: nil, isOfficial: official,
                              lastMessage: nil, unreadCount: 0, lastMessageAt: chatNow)
        }
        #expect(InboxFilter.buying.includes(row(.buyer)))
        #expect(!InboxFilter.buying.includes(row(.seller)))
        #expect(InboxFilter.selling.includes(row(.seller)))
        #expect(!InboxFilter.buying.includes(row(.buyer, official: true)))
        #expect(InboxFilter.all.includes(row(.buyer, official: true)))
    }

    @Test func aConversationHidesTheShellTabBar() {
        #expect(AppRoute.conversation(id: "c").hidesShellTabBar)
        #expect(AppRoute.listing(id: "l").hidesShellTabBar)
        #expect(!AppRoute.orders.hidesShellTabBar)
    }
}

// MARK: - Timeline

struct ChatTimelineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    @Test func outgoingFirstThenMessagesWithADayAboveEachDay() {
        let today = ChatMessage.fixture("m2", at: 0)
        let yesterday = ChatMessage.fixture("m1", at: -86_400)
        let empty = ChatMessage.fixture("pill", kind: .system, at: -10, text: nil)
        let outgoing = OutgoingMessage(draft: MessageDraft(clientId: "x", text: "Salut", photoKey: nil), photo: nil,
                                       createdAt: chatNow.addingTimeInterval(5), state: .sending)
        let rows = ChatTimeline.rows(outgoing: [outgoing], messages: [today, empty, yesterday], calendar: calendar)
        #expect(rows.map(\.id) == ["out-x", "m2", "day-\(Int(calendar.startOfDay(for: chatNow).timeIntervalSince1970))", "m1",
                                   "day-\(Int(calendar.startOfDay(for: yesterday.createdAt).timeIntervalSince1970))"])
    }

    @Test func drawableMessages() {
        #expect(!ChatMessage.fixture("a", kind: .unknown, text: nil).isDrawable)
        #expect(ChatMessage.fixture("b", kind: .unknown, text: "Nouveau").isDrawable)
        #expect(!ChatMessage.fixture("c", kind: .offer, text: nil).isDrawable)
        #expect(!ChatMessage.fixture("d", kind: .text, text: nil).isDrawable)
    }
}

// MARK: - Announcement HTML

struct AnnouncementHTMLTests {
    @Test func headingsParagraphsListsLinksAndImages() {
        let html = """
        <h2>Nouveau : les lots</h2><p>Achetez <strong>plusieurs</strong> articles&nbsp;&amp; payez \
        <a href="/browse">une fois</a>.</p><ul><li>Un colis</li><li>Une protection</li></ul>\
        <img src="/files/a.webp" alt=""><hr><ol><li>Choisir</li></ol>
        """
        let blocks = AnnouncementHTML.blocks(from: html, baseURL: URL(string: "https://taleed.app"))
        #expect(blocks.count == 7)
        guard case let .heading(level, title) = blocks[0] else { Issue.record("heading"); return }
        #expect(level == 2)
        #expect(String(title.characters) == "Nouveau : les lots")
        guard case let .paragraph(text) = blocks[1] else { Issue.record("paragraph"); return }
        #expect(String(text.characters) == "Achetez plusieurs articles\u{00A0}& payez une fois.")
        let link = text.runs.compactMap(\.link).first
        #expect(link?.absoluteString == "https://taleed.app/browse")
        #expect(blocks[2] == .listItem(marker: "•", depth: 0, AttributedString("Un colis")))
        #expect(blocks[4] == .image(URL(string: "https://taleed.app/files/a.webp")!))
        #expect(blocks[5] == .rule)
        #expect(blocks[6] == .listItem(marker: "1.", depth: 0, AttributedString("Choisir")))
    }

    @Test func entitiesAndUnsafeLinks() {
        #expect(AnnouncementHTML.decodeEntities("l&#39;offre &#x2014; &lt;b&gt;") == "l'offre — <b>")
        #expect(AnnouncementHTML.resolve("javascript:alert(1)", baseURL: nil) == nil)
        #expect(AnnouncementHTML.resolve("//evil.example", baseURL: nil) == nil)
        #expect(AnnouncementHTML.resolve("https://example.com/x", baseURL: nil)?.host() == "example.com")
    }

    @Test func plainTextBreaksOnBr() {
        let blocks = AnnouncementHTML.blocks(from: "Bonjour<br>à   tous", baseURL: nil)
        #expect(blocks == [.paragraph(AttributedString("Bonjour\nà tous"))])
    }
}
