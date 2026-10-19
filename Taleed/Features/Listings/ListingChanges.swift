import Foundation
import Observation

/// What the member's own actions changed on their listings (screens.md §2 G8), so that every screen in
/// the stacks shows it without a reload: the listing screen under the edit form, My listings under a
/// listing screen, the Active tab after publishing.
///
/// Screens keep the `seq` they applied and read `changes(after:)` when `seq` moves, as with
/// `FavoriteStore`. A change carries its `source`, so the screen that made it can skip its own.
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

    /// The changes kept for screens that catch up later (a screen deeper in a stack).
    static let capacity = 100

    func post(_ kind: Kind, listingId: String, source: UUID? = nil) {
        seq += 1
        log.append(Change(seq: seq, listingId: listingId, kind: kind, source: source))
        if log.count > Self.capacity { log.removeFirst(log.count - Self.capacity) }
    }

    /// The changes made after `seq`, oldest first. Nil when some were dropped from the log meanwhile:
    /// the screen reloads instead.
    func changes(after seq: Int) -> [Change]? {
        guard seq < self.seq else { return [] }
        guard let first = log.first, first.seq <= seq + 1 else { return nil }
        return log.filter { $0.seq > seq }
    }
}
