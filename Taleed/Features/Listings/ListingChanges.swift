import Foundation
import Observation

/// What the member's own actions changed on their listings (screens.md §2 G8), so that every screen in
/// the stacks shows it without a reload: the listing screen under the edit form, My listings under a
/// listing screen, the Active tab after publishing.
///
/// Screens keep the `seq` they applied and read `changes(after:)` when `seq` moves, as with
/// `FavoriteStore`. A change carries its `source`, so the screen that made it can skip its own.
///
/// The public grids (Home, Explore, a wardrobe, a listing's "more from this seller") pass their cards
/// through `cards(_:)`: an edited listing shows its new price, title and cover, a hidden one leaves.
@MainActor
@Observable
final class ListingChangeCenter {
    struct Change: Equatable, Sendable {
        let seq: Int
        let listingId: String
        let kind: Kind
        /// The screen (view model) that made the change; nil for none in particular.
        let source: UUID?
    }

    enum Kind: Equatable, Sendable {
        /// Edited, hidden or put back on sale: the listing as the API answered.
        case updated(ListingDetail)
        /// Deleted (or found gone).
        case deleted
        /// Just published.
        case created
        /// The server refused a change (`listing_locked`): the listing changed in a way the app does not
        /// know yet (reserved, sold), reload it.
        case stale
    }

    /// Moves with every change.
    private(set) var seq = 0
    @ObservationIgnored private var log: [Change] = []
    /// The member's listings as their last change left them, for the cards loaded before it.
    private(set) var latest: [String: ListingSummary] = [:]

    /// The changes kept for screens that catch up later (a screen deeper in a stack).
    static let capacity = 100

    func post(_ kind: Kind, listingId: String, source: UUID? = nil) {
        seq += 1
        log.append(Change(seq: seq, listingId: listingId, kind: kind, source: source))
        if log.count > Self.capacity { log.removeFirst(log.count - Self.capacity) }
        switch kind {
        case let .updated(detail): latest[listingId] = detail.summary
        // Deleted cards leave through `FavoriteStore.markRemoved`; a stale one shows what it loaded.
        case .deleted, .stale: latest[listingId] = nil
        case .created: break
        }
    }

    /// The cards of a public list with the member's changes made after they loaded: a card loaded
    /// before an edit shows the edited values, a listing hidden since leaves (slice B: a hidden listing
    /// leaves the public wardrobe). A card loaded after the change is the server's word and stays.
    func cards(_ items: [ListingSummary]) -> [ListingSummary] {
        guard !latest.isEmpty else { return items }
        return items.compactMap { card in
            guard let change = latest[card.id], change.asOf > card.asOf else { return card }
            guard change.status.isPublic else { return nil }
            return card.applying(change)
        }
    }

    /// The changes made after `seq`, oldest first. Nil when some were dropped from the log meanwhile:
    /// the screen reloads instead.
    func changes(after seq: Int) -> [Change]? {
        guard seq < self.seq else { return [] }
        guard let first = log.first, first.seq <= seq + 1 else { return nil }
        return log.filter { $0.seq > seq }
    }
}

extension ListingStatus {
    /// Shown to every member (hidden, draft and unknown listings are the seller's only).
    var isPublic: Bool {
        switch self {
        case .active, .reserved, .sold: true
        case .hidden, .draft, .unknown: false
        }
    }
}

extension ListingSummary {
    /// The card with what the seller changed (`change`), keeping its hearts and when it was loaded
    /// (`FavoriteStore` compares hearts by `asOf`).
    func applying(_ change: ListingSummary) -> ListingSummary {
        ListingSummary(id: id, title: change.title, price: change.price, size: change.size, brandName: change.brandName,
                       condition: change.condition, status: change.status, imageURL: change.imageURL,
                       favoritesCount: favoritesCount, isFavorited: isFavorited, isBoosted: change.isBoosted,
                       shipsFrom: change.shipsFrom, sellerRating: sellerRating, asOf: asOf)
    }
}
