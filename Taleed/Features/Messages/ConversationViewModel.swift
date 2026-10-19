import Foundation
import Observation
import UIKit

/// The conversation screen (screens.md §2 G9, slice C "The conversation screen" to "Live updates"):
/// the conversation and its last 40 messages, older pages as the member scrolls up, the live stream,
/// read marks, sending with an optimistic bubble, the photo, block and unblock.
@MainActor
@Observable
final class ConversationViewModel {
    /// What the screen tells with a toast.
    enum Notice: Equatable {
        case error(ApiError)
        /// "@x est bloqué."
        case blocked(handle: String)
        case unblocked(handle: String)
        /// A confirmation ("Offre envoyée !").
        case confirmation(L10nKey)
        /// Information ("Une offre est déjà en attente pour cet article.").
        case information(L10nKey)
    }

    let conversationId: String
    private(set) var conversation: ConversationDetail?
    /// The first load failed: the full-screen error (or "no longer available" for a `404`).
    private(set) var loadError: ApiError?
    private(set) var isLoading = false
    /// The server's messages, newest first, one per id.
    private(set) var messages: [ChatMessage] = []
    /// Sent by the member and not confirmed yet, newest first.
    private(set) var outgoing: [OutgoingMessage] = []
    private(set) var isLoadingOlder = false
    /// An older page failed: the top of the list offers "Réessayer".
    private(set) var olderError: ApiError?
    private(set) var photo: ComposerPhoto?
    private(set) var isChangingBlock = false
    /// The offer action running (G10); one at a time.
    var offerWork: ConversationOfferWork?
    /// The latest toast to show (the screen clears it).
    var notice: Notice?
    /// The composer's text, at most 2 000 characters.
    var text = "" {
        didSet {
            let limited = ChatText.limited(text)
            if limited != text { text = limited }
        }
    }

    var hasOlder: Bool { olderCursor != nil }

    @ObservationIgnored private var olderCursor: String?
    /// The latest state of each offer: every card of the same offer shows it (slice C, Messages). The offer
    /// actions (G10) record their answers in it.
    @ObservationIgnored var offers = ChatOfferStates()
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var hasMarkedRead = false
    @ObservationIgnored private let api: MessagesApi
    @ObservationIgnored private let events: ConversationEventsSource
    @ObservationIgnored private let members: MembersApi
    /// The offer actions (G10). Nil in tests that do not need them.
    @ObservationIgnored let offerApi: OffersApi?
    @ObservationIgnored private let upload: (Data) async throws(ApiError) -> UploadedPhoto
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let makeClientId: () -> String
    /// Called with the badges after each read mark (the tab badge and the bell).
    @ObservationIgnored var onRead: ((UnreadCounts) -> Void)?
    /// Called after each message the server confirmed (the push permission after the first one).
    @ObservationIgnored var onSent: (() -> Void)?

    init(conversationId: String, api: MessagesApi, events: ConversationEventsSource, members: MembersApi,
         offers: OffersApi? = nil,
         upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto, now: @escaping () -> Date = Date.init,
         makeClientId: @escaping () -> String = { UUID().uuidString.lowercased() }) {
        self.conversationId = conversationId
        self.api = api
        self.events = events
        self.members = members
        offerApi = offers
        self.upload = upload
        self.now = now
        self.makeClientId = makeClientId
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard conversation == nil, !isLoading else { return }
        await load()
    }

    /// The conversation, then its last page of messages; marks it read when the screen shows.
    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            #if DEBUG
            try DebugConversationFailure.next()
            #endif
            let detail = try await api.conversation(id: conversationId, automatic: false)
            let page = try await api.messages(conversationId: conversationId, cursor: nil, automatic: false)
            apply(detail)
            merge(page.items)
            olderCursor = page.nextCursor
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error
            return
        }
        if isVisible { await markRead() }
    }

    /// The header, the composer's state and the offer state again (after an offer message, a block, the
    /// return to the foreground). A `404` shows "no longer available".
    func reloadConversation(automatic: Bool) async {
        guard conversation != nil else { return }
        do {
            apply(try await api.conversation(id: conversationId, automatic: automatic))
        } catch {
            if error.isNotFound { loadError = error }
        }
    }

    /// The next older page, when the member reaches the top.
    func loadOlder() async {
        guard let cursor = olderCursor, !isLoadingOlder, conversation != nil else { return }
        isLoadingOlder = true
        olderError = nil
        defer { isLoadingOlder = false }
        do {
            let page = try await api.messages(conversationId: conversationId, cursor: cursor, automatic: false)
            merge(page.items)
            olderCursor = page.nextCursor
        } catch {
            guard !Task.isCancelled else { return }
            if error.isInvalidCursor {
                // The cursor expired: start again from the newest page; merging keeps every message once.
                if let page = try? await api.messages(conversationId: conversationId, cursor: nil, automatic: false) {
                    merge(page.items)
                    olderCursor = page.nextCursor
                }
            } else {
                olderError = error
            }
        }
    }

    private func apply(_ detail: ConversationDetail) {
        conversation = detail
        offers.record(pendingOffer: detail.pendingOffer)
    }

    // MARK: Messages

    /// Adds or replaces messages by id, newest first; a confirmed message replaces its "sending" bubble.
    func merge(_ incoming: [ChatMessage]) {
        guard !incoming.isEmpty else { return }
        var byId = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for message in incoming {
            byId[message.id] = message
        }
        offers.record(incoming)
        messages = byId.values.sorted { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
        let confirmed = Set(incoming.compactMap(\.clientId))
        if !confirmed.isEmpty { outgoing.removeAll { confirmed.contains($0.id) } }
    }

    /// The offer of a card as it stands now: an `OFFER_UPDATE` or the conversation may be newer than the
    /// card's own message.
    func offer(in message: ChatMessage) -> ChatOffer? {
        message.offer.map(offers.current)
    }

    /// The time the offer cards and buttons are drawn for.
    var currentDate: Date { now() }

    /// The rows to draw, newest first: the bubbles on their way, the messages, and a day above each day.
    func rows(calendar: Calendar = .current) -> [ChatRow] {
        ChatTimeline.rows(outgoing: outgoing, messages: messages, calendar: calendar)
    }

    // MARK: Visibility and read marks

    /// The screen is on top of the selected tab, with the app in the foreground.
    func setVisible(_ visible: Bool) async {
        guard visible != isVisible else { return }
        isVisible = visible
        guard visible, conversation != nil else { return }
        if !hasMarkedRead { await markRead() }
        // Back on screen: what the member missed comes through the stream, which reopens now.
        await retryFailed()
    }

    /// `POST /conversations/{id}/read`, then the badges it answers.
    private func markRead() async {
        hasMarkedRead = true
        guard let counts = try? await api.markRead(conversationId: conversationId) else { return }
        onRead?(counts)
    }

    // MARK: Live updates

    /// Reads the live stream while the screen shows (the view's task ends it when the screen goes away
    /// or the app goes to the background).
    func followLiveUpdates() async {
        guard conversation != nil, loadError == nil else { return }
        do {
            for try await event in events.events(conversationId: conversationId, after: messages.first?.id) {
                switch event {
                case .connected:
                    await retryFailed()
                case let .message(message):
                    await receive(message)
                }
            }
        } catch let error as ApiError {
            // `401` and `403 banned` are handled for the whole app; a gone conversation shows as such.
            if error.isNotFound { loadError = error } else if error.code == .forbidden { await reloadConversation(automatic: true) }
        } catch {}
    }

    /// One message from the stream: merged by id; the other member's marks the conversation read while
    /// it is on screen; an offer message reloads the offer state.
    func receive(_ message: ChatMessage) async {
        let isNew = !messages.contains { $0.id == message.id }
        merge([message])
        if isNew, !message.isMine, isVisible { await markRead() }
        if message.changesOfferState { await reloadConversation(automatic: true) }
    }

    // MARK: Sending

    var canSend: Bool {
        ComposerPhoto.canSend(canReply: conversation?.canReply == true, text: text, photo: photo)
    }

    /// Shows the bubble at once, marked "sending", and posts it.
    func send() async {
        guard canSend else { return }
        let draft = MessageDraft(clientId: makeClientId(), text: ChatText.sendableText(text), photoKey: photo?.key)
        outgoing.insert(OutgoingMessage(draft: draft, photo: photo?.preview, createdAt: now(), state: .sending), at: 0)
        text = ""
        photo = nil
        await deliver(draft.clientId)
    }

    /// "Réessayer" on a bubble that was not sent: the same `clientId`, so it is posted once at most.
    func retry(_ clientId: String) async {
        guard let index = outgoing.firstIndex(where: { $0.id == clientId }), outgoing[index].state == .failed else { return }
        await deliver(clientId)
    }

    /// Sends again what failed for lack of network, once the stream connects again or the screen
    /// shows again.
    private func retryFailed() async {
        for message in outgoing where message.state == .failed {
            await deliver(message.id)
        }
    }

    private func deliver(_ clientId: String) async {
        guard let index = outgoing.firstIndex(where: { $0.id == clientId }) else { return }
        outgoing[index].state = .sending
        let draft = outgoing[index].draft
        do {
            let message = try await api.sendMessage(conversationId: conversationId, draft: draft)
            outgoing.removeAll { $0.id == clientId }
            merge([message])
            onSent?()
        } catch {
            sendFailed(clientId: clientId, draft: draft, error: error)
        }
    }

    private func sendFailed(clientId: String, draft: MessageDraft, error: ApiError) {
        let outcome = ChatSendFailure(error)
        if outcome == .keep {
            // The answer may have been lost: the bubble stays, and a retry with the same id is safe.
            if let index = outgoing.firstIndex(where: { $0.id == clientId }) { outgoing[index].state = .failed }
        } else {
            outgoing.removeAll { $0.id == clientId }
        }
        switch outcome {
        case .keep:
            if case .rateLimited = error { notice = .error(error) }
        case .drop:
            break
        case .dropAndReload:
            // The conversation no longer takes replies: reload it to show why (slice C, Sending).
            notice = .error(error)
            Task { await reloadConversation(automatic: false) }
        case .dropAndRestoreText:
            // Refused as written: the text comes back to the composer.
            notice = .error(error)
            if text.isEmpty, let words = draft.text { text = words }
        }
    }

    // MARK: Photo

    /// Attaches a picked photo and uploads it at once (`chat_photo`, 1600 px JPEG).
    func attachPhoto(_ data: Data) async {
        guard photo == nil, conversation?.canReply == true, let image = UIImage(data: data) else { return }
        let id = UUID()
        let preview = image.preparingThumbnail(of: ComposerPhoto.previewSize(for: image.size)) ?? image
        photo = ComposerPhoto(id: id, preview: preview)
        do {
            let uploaded = try await upload(data)
            guard photo?.id == id else { return }
            photo?.key = uploaded.key
        } catch {
            guard photo?.id == id else { return }
            photo = nil
            notice = .error(error)
        }
    }

    func removePhoto() {
        photo = nil
    }

    // MARK: Menu, block and unblock

    var menuActions: ConversationMenuActions {
        conversation.map(ConversationMenuActions.init) ?? ConversationMenuActions()
    }

    /// `PUT` or `DELETE /members/{username}/block`, then the conversation again so that its flags apply.
    func setBlocked(_ blocked: Bool) async {
        guard let member = conversation?.counterpart, let username = member.username, !isChangingBlock else { return }
        isChangingBlock = true
        defer { isChangingBlock = false }
        do {
            try await members.setBlocked(username: username, blocked: blocked)
            await reloadConversation(automatic: false)
            notice = blocked ? .blocked(handle: member.displayName) : .unblocked(handle: member.displayName)
        } catch {
            notice = .error(error)
            if error.isNotFound { await reloadConversation(automatic: false) }
        }
    }

    // MARK: Foreground

    /// Back from the background: the conversation's state again (a block, an offer answered meanwhile);
    /// the messages come through the stream.
    func returnedToForeground() async {
        await reloadConversation(automatic: true)
    }
}
