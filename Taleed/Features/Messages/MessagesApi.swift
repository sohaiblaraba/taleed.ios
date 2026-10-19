import SwiftUI
import TaleedAPI

/// The calls of the inbox and the conversation screen (screens.md §2 G9, slice C "Inbox" to "Live
/// updates"). The live stream is `ConversationEventsSource`; blocking goes through `MembersApi`,
/// reporting through `ReportsApi`, photos through `PhotoUploadService` (`chat_photo`).
@MainActor
protocol MessagesApi: AnyObject {
    /// `GET /conversations`: most recent activity first, 30 a page. `automatic`: a reload the member did
    /// not ask for (return to the foreground, back from a conversation).
    func conversations(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<InboxConversation>
    /// `GET /conversations/{id}`: the header, the composer or why it is off, the offer state.
    func conversation(id: String, automatic: Bool) async throws(ApiError) -> ConversationDetail
    /// `GET /conversations/{id}/messages`: newest first, 40 a page; `nextCursor` goes back in time.
    func messages(conversationId: String, cursor: String?, automatic: Bool) async throws(ApiError) -> Page<ChatMessage>
    /// `POST /conversations/{id}/messages`. Safe to repeat with the same `clientId`: a repeat returns
    /// the message already posted.
    func sendMessage(conversationId: String, draft: MessageDraft) async throws(ApiError) -> ChatMessage
    /// `POST /conversations/{id}/read`: the badges after the change. Idempotent.
    func markRead(conversationId: String) async throws(ApiError) -> UnreadCounts
}

extension GeneratedTaleedApi: MessagesApi {
    func conversations(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<InboxConversation> {
        let page = try await caller.call(.read, automatic: automatic) {
            try await ConversationsAPI.listConversations(cursor: cursor, apiConfiguration: $0)
        }
        return Page(items: page.items.map(InboxConversation.init), nextCursor: page.nextCursor, total: page.total)
    }

    func conversation(id: String, automatic: Bool) async throws(ApiError) -> ConversationDetail {
        let conversation = try await caller.call(.read, automatic: automatic) {
            try await ConversationsAPI.getConversation(id: id, apiConfiguration: $0)
        }
        return ConversationDetail(conversation)
    }

    func messages(conversationId: String, cursor: String?, automatic: Bool) async throws(ApiError) -> Page<ChatMessage> {
        let page = try await caller.call(.read, automatic: automatic) {
            try await ConversationsAPI.listMessages(id: conversationId, cursor: cursor, apiConfiguration: $0)
        }
        return Page(items: page.items.map(ChatMessage.init), nextCursor: page.nextCursor, total: page.total)
    }

    func sendMessage(conversationId: String, draft: MessageDraft) async throws(ApiError) -> ChatMessage {
        let body = MessageCreate(text: draft.text, photoKey: draft.photoKey, clientId: draft.clientId)
        // The `clientId` makes a repeat return the message already posted (slice C, Sending): repeated
        // after no answer or a 5xx like a read (screens.md §0.6), then the bubble offers "Réessayer".
        #if DEBUG
        try DebugSendFailure.beforeSend()
        #endif
        let message = try await caller.call(.read) {
            try await ConversationsAPI.sendMessage(id: conversationId, messageCreate: body, apiConfiguration: $0)
        }
        #if DEBUG
        try DebugSendFailure.afterSend()
        #endif
        return ChatMessage(message)
    }

    func markRead(conversationId: String) async throws(ApiError) -> UnreadCounts {
        // Idempotent (slice C, Read state).
        let counts = try await caller.call(.read, automatic: true) {
            try await ConversationsAPI.markConversationRead(id: conversationId, apiConfiguration: $0)
        }
        return UnreadCounts(messages: counts.unreadMessages, notifications: counts.unreadNotifications)
    }
}

/// What the Messages tab and the conversation screen need. Set once at the root (`AppRootView`).
struct MessagesDependencies {
    let messages: any MessagesApi
    let events: any ConversationEventsSource
    let members: any MembersApi
    let reports: any ReportsApi
    let uploads: PhotoUploadService
    /// The conversations the member just read, for the inbox's rows.
    let reads: ConversationReads
}

/// Tells the inbox which conversation the member just read (`POST /conversations/{id}/read`
/// answered), so that its row loses the bold and the counter at once, as the tab badge does
/// (screens.md §2 G9), even when the inbox does not reload on the way back.
@MainActor
@Observable
final class ConversationReads {
    struct Mark: Equatable {
        let conversationId: String
        /// Tells two reads of the same conversation apart.
        let sequence: Int
    }

    /// The latest read.
    private(set) var latest: Mark?

    func didRead(conversationId: String) {
        latest = Mark(conversationId: conversationId, sequence: (latest?.sequence ?? 0) + 1)
    }
}

private struct MessagesDependenciesKey: EnvironmentKey {
    static var defaultValue: MessagesDependencies? { nil }
}

extension EnvironmentValues {
    var messagesDependencies: MessagesDependencies? {
        get { self[MessagesDependenciesKey.self] }
        set { self[MessagesDependenciesKey.self] = newValue }
    }
}

// MARK: - Mapping

extension ChatMember {
    init(_ member: MemberSummary) {
        self.init(
            id: member.id,
            username: member.username,
            displayName: member.displayName,
            avatarURL: URL(apiString: member.avatarUrl),
            isVerified: member.isVerified,
            isOfficial: member.isOfficial
        )
    }
}

extension ChatRole {
    init(_ role: ConversationRole) {
        switch role {
        case .buyer: self = .buyer
        case .seller: self = .seller
        case .unknownDefaultOpenApi: self = .unknown
        }
    }
}

extension ChatListing {
    init(_ listing: ConversationListing) {
        let status: ChatListingStatus = switch listing.status {
        case .active: .active
        case .reserved: .reserved
        case .sold: .sold
        case .hidden: .hidden
        case .removed: .removed
        case .unknownDefaultOpenApi: .unknown
        }
        self.init(id: listing.id, title: listing.title, price: listing.price, imageURL: URL(apiString: listing.imageUrl),
                  status: status)
    }
}

extension InboxConversation {
    init(_ summary: ConversationSummary) {
        self.init(
            id: summary.id,
            role: ChatRole(summary.role),
            counterpart: summary.counterpart.map(ChatMember.init),
            listing: summary.listing.map(ChatListing.init),
            isOfficial: summary.isOfficial,
            lastMessage: summary.lastMessage.map { ChatPreview(text: $0.text, isMine: $0.isMine, createdAt: $0.createdAt) },
            unreadCount: summary.unreadCount,
            lastMessageAt: summary.lastMessageAt
        )
    }
}

extension ConversationDetail {
    init(_ conversation: Conversation) {
        let block: ReplyBlock? = conversation.replyDisabledReason.map { reason in
            switch reason {
            case .official: .official
            case .blocked: .blocked
            case .memberDeleted: .memberDeleted
            case .unknownDefaultOpenApi: .unknown
            }
        }
        self.init(
            id: conversation.id,
            role: ChatRole(conversation.role),
            counterpart: conversation.counterpart.map(ChatMember.init),
            listing: conversation.listing.map(ChatListing.init),
            isOfficial: conversation.isOfficial,
            unreadCount: conversation.unreadCount,
            canReply: conversation.canReply,
            replyBlock: block,
            isBlocked: conversation.isBlocked,
            offerRange: conversation.offerRange.map { AmountRange(min: $0.min, max: $0.max) },
            pendingOffer: conversation.pendingOffer.map(ChatOffer.init)
        )
    }
}

extension ChatOfferStatus {
    init(_ status: OfferStatus) {
        switch status {
        case .pending: self = .pending
        case .accepted: self = .accepted
        case .declined: self = .declined
        case .countered: self = .countered
        case .cancelled: self = .cancelled
        case .expired: self = .expired
        case .unknownDefaultOpenApi: self = .unknown
        }
    }
}

extension ChatBundle {
    init(_ lot: BundleLot) {
        self.init(
            id: lot.id,
            items: lot.items.map {
                ChatBundleItem(listingId: $0.listingId, title: $0.title, price: $0.price, imageURL: URL(apiString: $0.imageUrl))
            },
            itemsTotal: lot.itemsTotal
        )
    }
}

extension ChatOffer {
    init(_ offer: Offer) {
        self.init(
            id: offer.id,
            amount: offer.amount,
            status: ChatOfferStatus(offer.status),
            expiresAt: offer.expiresAt,
            createdAt: offer.createdAt,
            senderId: offer.senderId,
            isMine: offer.isMine,
            sentBy: ChatRole(offer.sentBy),
            listingId: offer.listingId,
            bundle: offer.bundle.map(ChatBundle.init),
            canAccept: offer.canAccept,
            canDecline: offer.canDecline,
            canCounter: offer.canCounter,
            canCancel: offer.canCancel,
            canPay: offer.canPay,
            counterRange: offer.counterRange.map { AmountRange(min: $0.min, max: $0.max) }
        )
    }
}

extension ChatMessageKind {
    init(_ kind: MessageKind) {
        switch kind {
        case .text: self = .text
        case .offer: self = .offer
        case .offerUpdate: self = .offerUpdate
        case .bundle: self = .bundle
        case .orderUpdate: self = .orderUpdate
        case .system: self = .system
        case .unknownDefaultOpenApi: self = .unknown
        }
    }
}

extension ChatOrderMilestone {
    init(_ milestone: OrderMilestone) {
        switch milestone {
        case .paid: self = .paid
        case .shipped: self = .shipped
        case .atStopdesk: self = .atStopdesk
        case .outForDelivery: self = .outForDelivery
        case .delivered: self = .delivered
        case .completed: self = .completed
        case .unknownDefaultOpenApi: self = .unknown
        }
    }
}

extension ChatMessage {
    init(_ message: Message) {
        self.init(
            id: message.id,
            kind: ChatMessageKind(message.kind),
            senderId: message.senderId,
            isMine: message.isMine,
            createdAt: message.createdAt,
            clientId: message.clientId,
            text: message.text,
            html: message.html,
            photoURL: URL(apiString: message.photoUrl),
            callToAction: message.cta.map { ChatCallToAction(label: $0.label, url: URL(apiString: $0.url)) },
            offer: message.offer.map(ChatOffer.init),
            offerEvent: message.offerEvent.map(ChatOfferStatus.init),
            bundle: message.bundle.map(ChatBundle.init),
            order: message.order.map { ChatOrderRef(id: $0.id, milestone: ChatOrderMilestone($0.milestone)) }
        )
    }
}
