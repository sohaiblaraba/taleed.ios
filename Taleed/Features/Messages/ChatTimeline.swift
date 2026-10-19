import Foundation
import UIKit

/// A message the member sent that the server has not confirmed yet: the "sending" bubble, then
/// "Non envoyé · Réessayer" when the automatic retries gave up (slice C, Sending).
struct OutgoingMessage: Identifiable {
    enum State: Equatable {
        case sending, failed
    }

    /// Sent again as it is on every retry: its `clientId` makes the API return the message already posted.
    let draft: MessageDraft
    /// The photo from the device while it is on its way.
    let photo: UIImage?
    let createdAt: Date
    var state: State

    var id: String { draft.clientId }
}

/// A row of the conversation, newest first (the list is drawn from the bottom up).
enum ChatRow: Identifiable {
    case outgoing(OutgoingMessage)
    case message(ChatMessage)
    /// The day of the messages below it in time ("Aujourd'hui").
    case day(Date)

    var id: String {
        switch self {
        case let .outgoing(message): "out-\(message.id)"
        case let .message(message): message.id
        case let .day(date): "day-\(Int(date.timeIntervalSince1970))"
        }
    }
}

/// The photo attached in the composer: uploaded as soon as it is picked (as the website), so that
/// sending stays instant. One photo per message.
struct ComposerPhoto {
    let id: UUID
    let preview: UIImage
    /// The `chat_photo` key once uploaded.
    var key: String?

    var isUploading: Bool { key == nil }

    /// The bubble's copy of a photo: 800 px on the longer side is plenty for the screen.
    static func previewSize(for size: CGSize) -> CGSize {
        PhotoPreparer.fittedSize(size, within: CGSize(width: 800, height: 800))
    }

    /// "Envoyer" works while replies are open, no photo is uploading, and there is text or a photo.
    static func canSend(canReply: Bool, text: String, photo: ComposerPhoto?) -> Bool {
        guard canReply, !(photo?.isUploading ?? false) else { return false }
        return ChatText.sendableText(text) != nil || photo?.key != nil
    }
}

extension ChatMessage {
    /// Whether the message draws anything: a pill without text, an offer card without its offer… draw
    /// nothing (slice C: an unknown kind without `text`).
    var isDrawable: Bool {
        switch kind {
        case .text: text?.isEmpty == false || html?.isEmpty == false || photoURL != nil
        case .offer: offer != nil
        case .bundle: bundle != nil
        case .offerUpdate, .orderUpdate, .system, .unknown: text?.isEmpty == false
        }
    }

    /// An offer, an answer to one or a bundle card changes `pendingOffer` and `offerRange`: the live
    /// stream reloads the conversation for these (slice C, Live updates).
    var changesOfferState: Bool {
        kind == .offer || kind == .offerUpdate || kind == .bundle
    }
}

/// The rows of a conversation, newest first (the list is drawn from the bottom up).
enum ChatTimeline {
    /// The bubbles on their way first, then the server's messages that draw something, with the day
    /// after (above, on screen) the last message of each day.
    static func rows(outgoing: [OutgoingMessage], messages: [ChatMessage], calendar: Calendar) -> [ChatRow] {
        let pending: [(Date, ChatRow)] = outgoing.map { ($0.createdAt, .outgoing($0)) }
        let posted: [(Date, ChatRow)] = messages.filter(\.isDrawable).map { ($0.createdAt, .message($0)) }
        let entries = pending + posted
        var rows: [ChatRow] = []
        for (index, entry) in entries.enumerated() {
            rows.append(entry.1)
            let older = index + 1 < entries.count ? entries[index + 1].0 : nil
            if older.map({ !calendar.isDate($0, inSameDayAs: entry.0) }) ?? true {
                rows.append(.day(calendar.startOfDay(for: entry.0)))
            }
        }
        return rows
    }
}

/// The conversation menu's entries (slice C: Report, Block or Unblock, View listing, View profile).
struct ConversationMenuActions: Equatable {
    var report = false
    var block = false
    var unblock = false
    var viewListing = false
    var viewProfile = false
}

extension ConversationMenuActions {
    init(_ conversation: ConversationDetail) {
        let member = conversation.counterpart
        let canTargetMember = member?.username != nil && member?.isOfficial == false && !conversation.isOfficial
        self.init(
            // Official threads have nothing to report (the website hides it too).
            report: !conversation.isOfficial,
            block: canTargetMember && !conversation.isBlocked,
            unblock: member?.username != nil && conversation.isBlocked,
            viewListing: conversation.listing != nil,
            viewProfile: member?.username != nil
        )
    }
}

/// What a failed send does with its bubble (slice C, Sending).
enum ChatSendFailure: Equatable {
    /// No answer, a 5xx or a `429`: the bubble stays, "Non envoyé · Réessayer" (same `clientId`).
    case keep
    /// `401` or `403 banned`: handled for the whole app.
    case drop
    /// `403 blocked`, `conversation_read_only`, `forbidden`, `404`: the conversation no longer takes
    /// replies; it reloads to show why.
    case dropAndReload
    /// Refused as written (`invalid_request`…): the text comes back to the composer.
    case dropAndRestoreText

    init(_ error: ApiError) {
        switch error {
        case .network, .server, .rateLimited:
            self = .keep
        case .unauthorized, .banned:
            self = .drop
        default:
            switch error.code {
            case .blocked, .conversationReadOnly, .forbidden, .notFound: self = .dropAndReload
            default: self = .dropAndRestoreText
            }
        }
    }
}

#if DEBUG
/// `-TaleedDebugConversation offline` fails the first conversation load of the run (then works).
@MainActor
enum DebugConversationFailure {
    private static var failedOnce = false

    static func next() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugConversation") == "offline", !failedOnce else { return }
        failedOnce = true
        throw .network
    }
}

/// `-TaleedDebugSend lost`: the first message of the run reaches the server but its answer is "lost"
/// (as offline); the live stream or "Réessayer" (same `clientId`) confirms the one message posted.
/// `-TaleedDebugSend offline`: the first message fails before it leaves (as in airplane mode), so the
/// bubble shows "Non envoyé" until "Réessayer" (slice C, Sending).
@MainActor
enum DebugSendFailure {
    private static var failedOnce = false

    static func beforeSend() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugSend") == "offline", !failedOnce else { return }
        failedOnce = true
        throw .network
    }

    static func afterSend() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugSend") == "lost", !failedOnce else { return }
        failedOnce = true
        throw .network
    }
}
#endif
