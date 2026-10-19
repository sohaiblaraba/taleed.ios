import Foundation

// The app models of the inbox and the conversation screen (screens.md §2 G9, slice C). Values the build
// does not know decode as `.unknown` (api-guide.md, Compatibility); every permission comes from the
// server's flags (`canReply`, `isBlocked`, the offer's `can…`).

/// The other member of a conversation: their handle, never a real name (screens.md §0.3).
struct ChatMember: Equatable, Sendable {
    let id: String
    /// Nil for the few accounts older than usernames: no profile link then.
    let username: String?
    let displayName: String
    let avatarURL: URL?
    let isVerified: Bool
    let isOfficial: Bool
}

/// The signed-in member's side of the conversation.
enum ChatRole: Equatable, Sendable {
    case buyer, seller, unknown
}

/// Where the listing of a conversation stands now (`ConversationListingStatus`).
enum ChatListingStatus: Equatable, Sendable {
    case active, reserved, sold
    /// Paused by its seller, or not published.
    case hidden
    /// Deleted; the conversation stays.
    case removed
    case unknown
}

/// The listing a conversation is about. Nil on official threads.
struct ChatListing: Equatable, Sendable {
    let id: String
    let title: String
    /// The current asking price.
    let price: Int
    let imageURL: URL?
    let status: ChatListingStatus
}

/// The inbox's one line about the last message, already in the response language ("📷 Photo",
/// "Offre · 2 500 DA", "Message automatique").
struct ChatPreview: Equatable, Sendable {
    let text: String
    let isMine: Bool
    let createdAt: Date
}

/// A conversation in the inbox (`GET /conversations`).
struct InboxConversation: Identifiable, Equatable, Sendable {
    let id: String
    let role: ChatRole
    /// Nil when the other member deleted their account.
    let counterpart: ChatMember?
    let listing: ChatListing?
    /// Taleed's announcement thread: no composer.
    let isOfficial: Bool
    /// Nil while nothing was sent.
    let lastMessage: ChatPreview?
    var unreadCount: Int
    let lastMessageAt: Date
}

/// Why the composer is off (`replyDisabledReason`).
enum ReplyBlock: Equatable, Sendable {
    case official
    /// One of the two members blocked the other: `isBlocked` says who.
    case blocked
    case memberDeleted
    /// A reason added after this build: a generic text.
    case unknown
}

/// A conversation as its screen shows it (`GET /conversations/{id}`).
struct ConversationDetail: Identifiable, Equatable, Sendable {
    let id: String
    let role: ChatRole
    let counterpart: ChatMember?
    let listing: ChatListing?
    let isOfficial: Bool
    let unreadCount: Int
    /// Show the composer; otherwise the reason in its place.
    let canReply: Bool
    let replyBlock: ReplyBlock?
    /// The signed-in member blocked the other: "Unblock" in place of the composer.
    let isBlocked: Bool
    /// The bounds of an offer made from the conversation (G10). Nil when none can be made.
    let offerRange: AmountRange?
    /// The offer waiting for an answer, whoever made it (G10 pins it).
    let pendingOffer: ChatOffer?
    /// For the buyer: the newest accepted offer they can still pay, however old its messages (API 1.5.7).
    /// G10 pins "Payer maintenant · X" with it. Nil for the seller.
    let payableOffer: ChatOffer?
}

/// `offer.status`, and `offerEvent` on `OFFER_UPDATE` messages.
enum ChatOfferStatus: Equatable, Sendable {
    case pending, accepted, declined, countered, cancelled, expired
    /// A status added after this build: a neutral "closed" card.
    case unknown
}

/// An item of a bundle an offer prices or a question is about.
struct ChatBundleItem: Identifiable, Equatable, Sendable {
    let listingId: String
    let title: String
    /// The price when it was added to the bundle.
    let price: Int
    let imageURL: URL?

    var id: String { listingId }
}

/// The items of a bundle (`BundleLot`).
struct ChatBundle: Equatable, Sendable {
    let id: String
    /// In the buyer's order; the first one is the conversation's listing.
    let items: [ChatBundleItem]
    let itemsTotal: Int
}

/// An offer, or a price the seller proposed. Its buttons (G10) follow the `can…` flags only.
struct ChatOffer: Identifiable, Equatable, Sendable {
    let id: String
    let amount: Int
    let status: ChatOfferStatus
    let expiresAt: Date
    let createdAt: Date
    let senderId: String
    let isMine: Bool
    /// `buyer` for a buyer's offer, `seller` for a price the seller proposed.
    let sentBy: ChatRole
    let listingId: String
    /// Set when the offer prices a whole bundle.
    let bundle: ChatBundle?
    let canAccept: Bool
    let canDecline: Bool
    let canCounter: Bool
    let canCancel: Bool
    let canPay: Bool
    let counterRange: AmountRange?

    /// The status to show at `now`: a pending offer lapses at `expiresAt` without any message (slice C).
    func displayStatus(at now: Date) -> ChatOfferStatus {
        status == .pending && expiresAt <= now ? .expired : status
    }
}

/// How to draw a message (`MessageKind`).
enum ChatMessageKind: Equatable, Sendable {
    case text, offer, offerUpdate, bundle, orderUpdate, system
    /// A kind added after this build: drawn like `system`, a pill with `text`, or nothing.
    case unknown
}

/// An order step posted in the conversation (`OrderMilestone`).
enum ChatOrderMilestone: Equatable, Sendable {
    case paid, shipped, atStopdesk, outForDelivery, delivered, completed, unknown
}

/// `ORDER_UPDATE`: the order and its step.
struct ChatOrderRef: Equatable, Sendable {
    let id: String
    let milestone: ChatOrderMilestone
}

/// The button under an official announcement: routed like a push link.
struct ChatCallToAction: Equatable, Sendable {
    let label: String
    let url: URL?
}

/// A message (`Message`), as the list, the send answer and the live stream give it.
struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: String
    let kind: ChatMessageKind
    /// The member who sent it; on automatic messages, the member whose action produced it.
    let senderId: String
    let isMine: Bool
    let createdAt: Date
    /// The app's id for a message it sent, to replace the "sending" bubble.
    let clientId: String?
    /// `TEXT`: the words (nil for a photo alone). Pills: their localized text.
    let text: String?
    /// Official announcements only: sanitized HTML to show instead of `text`.
    let html: String?
    let photoURL: URL?
    let callToAction: ChatCallToAction?
    /// `OFFER`: the offer. `OFFER_UPDATE`: that offer as it stands now.
    let offer: ChatOffer?
    /// `OFFER_UPDATE`: what happened to the offer.
    let offerEvent: ChatOfferStatus?
    let bundle: ChatBundle?
    let order: ChatOrderRef?
}

/// The badges after `POST /conversations/{id}/read`.
struct UnreadCounts: Equatable, Sendable {
    let messages: Int
    let notifications: Int
}

/// What a member sends: text, a photo, or a photo with a caption, and the id that makes a retry safe.
struct MessageDraft: Equatable, Sendable {
    let clientId: String
    let text: String?
    let photoKey: String?
}
