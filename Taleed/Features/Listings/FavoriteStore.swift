import Foundation
import Observation

/// The hearts of every listing card and listing screen (slice B, Favorites), so that a heart tapped
/// on one screen shows on the others without a reload.
///
/// A tap fills or empties the heart at once and moves the count; the API's answer then sets both.
/// Taps made while a request runs are kept: once it answers, the store sends what the member asked
/// for last. On a failure the heart goes back to the last state the API confirmed. `404 not_found`
/// (the listing was deleted, taken down or hidden) puts the id in `removedIds`: lists leave the card out.
///
/// The server stays the source of truth (screens.md §0.1): the store's state only covers the cards
/// the app asked for before the change. A card asked for after the request settled (pull-to-refresh,
/// the foreground reload, another list) shows the server's heart and count again, including changes
/// made by other members or on the website.
///
/// Every change the API confirmed is also logged in `changes` (with `changeSeq`), so that the favorites
/// screen adds the cards hearted elsewhere at its top and drops the ones un-hearted, without a reload.
@MainActor
@Observable
final class FavoriteStore {
    /// A heart the member changed in this session.
    struct Override: Equatable, Sendable {
        var state: FavoriteState
        /// When the API's answer (or the failure) arrived; nil while a request runs, when the override
        /// wins over every card.
        var settledAt: ContinuousClock.Instant?

        /// Whether it wins over a card asked for at `asOf`.
        func applies(to asOf: ContinuousClock.Instant) -> Bool {
            settledAt.map { asOf < $0 } ?? true
        }
    }

    /// What the member changed in this session, by listing id. Wins over cards asked for before it settled.
    private(set) var overrides: [String: Override] = [:]
    /// Listings that answered `404`.
    private(set) var removedIds: Set<String> = []
    /// Bumped by every entry of `changes`: the favorites screen follows it to add and remove its cards.
    private(set) var changeSeq = 0

    /// The changes of this session's member, oldest first (`changes(after:)`).
    @ObservationIgnored private(set) var changes: [FavoriteChange] = []

    /// A favorite could not be changed (not a `404`): the app's toast.
    @ObservationIgnored var onFailure: ((ApiError) -> Void)?
    /// A favorite answered `404`: "no longer available".
    @ObservationIgnored var onRemoved: ((String) -> Void)?

    @ObservationIgnored private let api: FavoritesApi
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    /// The state the API last confirmed while requests for a listing run (the card's state before the
    /// first tap): a failure goes back to it.
    @ObservationIgnored private var confirmed: [String: FavoriteState] = [:]
    /// What the member asked for last, while a request for that listing runs.
    @ObservationIgnored private var wanted: [String: Bool] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    /// The card of each listing whose request runs, for `changes`.
    @ObservationIgnored private var cards: [String: ListingSummary] = [:]

    init(api: FavoritesApi, now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.api = api
        self.now = now
    }

    /// The heart and count to draw for a listing.
    func state(for listing: ListingSummary) -> FavoriteState {
        if let override = overrides[listing.id], override.applies(to: listing.asOf) { return override.state }
        return FavoriteState(isFavorited: listing.isFavorited, count: listing.favoritesCount)
    }

    /// The heart's tap, signed in. Returns the request it started (tests wait on it).
    @discardableResult
    func toggle(_ listing: ListingSummary) -> Task<Void, Never>? {
        setFavorite(listing, to: !state(for: listing).isFavorited)
    }

    /// Adds or removes a favorite. After signing in from a heart, call it with `true`: the card came
    /// from a signed-out list, so a toggle could remove a favorite the member already had.
    @discardableResult
    func setFavorite(_ listing: ListingSummary, to favorited: Bool) -> Task<Void, Never>? {
        let id = listing.id
        let current = state(for: listing)
        let isRunning = inFlight.contains(id)
        if !isRunning { confirmed[id] = current }
        wanted[id] = favorited
        let shown = current.isFavorited == favorited
            ? current
            : FavoriteState(isFavorited: favorited, count: max(0, current.count + (favorited ? 1 : -1)))
        overrides[id] = Override(state: shown, settledAt: nil)
        cards[id] = listing
        // Sent even when the heart already shows that state (after a sign-in): both calls are idempotent.
        guard !isRunning else { return nil }
        inFlight.insert(id)
        return Task { await send(id) }
    }

    /// A listing that is gone (deleted by its seller, or `404` on its screen): lists leave its card out.
    func markRemoved(_ id: String) {
        removedIds.insert(id)
        record(.removed(id: id))
    }

    /// The changes that settled after `seq` (a `changeSeq` read earlier), oldest first.
    func changes(after seq: Int) -> [FavoriteChange] {
        changes.filter { $0.seq > seq }
    }

    /// The session changed (sign-in, sign-out, another account): the lists reload with the new
    /// member's hearts, so the changes of the previous one no longer apply. Requests still running
    /// keep their answer.
    func sessionDidChange() {
        overrides = overrides.filter { inFlight.contains($0.key) }
        confirmed = confirmed.filter { inFlight.contains($0.key) }
        changes = []
    }

    private func send(_ id: String) async {
        guard let favorited = wanted[id] else {
            finish(id, with: confirmed[id])
            return
        }
        do {
            let answer = try await api.setFavorite(listingId: id, favorited: favorited)
            confirmed[id] = answer
            if let latest = wanted[id], latest != answer.isFavorited {
                // The member tapped again meanwhile: send the latest wish.
                await send(id)
                return
            }
            let card = cards[id]
            finish(id, with: answer)
            if answer.isFavorited, let card {
                record(.added(card))
            } else if !answer.isFavorited {
                record(.removed(id: id))
            }
        } catch {
            finish(id, with: confirmed[id])
            if error.isNotFound {
                removedIds.insert(id)
                record(.removed(id: id))
                onRemoved?(id)
            } else {
                onFailure?(error)
            }
        }
    }

    /// The last request for a listing settled: its state holds until a card asked for later arrives.
    private func finish(_ id: String, with state: FavoriteState?) {
        if let state {
            overrides[id] = Override(state: state, settledAt: now())
        } else {
            overrides[id] = nil
        }
        wanted[id] = nil
        confirmed[id] = nil
        cards[id] = nil
        inFlight.remove(id)
    }

    private func record(_ kind: FavoriteChange.Kind) {
        changeSeq += 1
        changes.append(FavoriteChange(seq: changeSeq, kind: kind))
    }
}

/// A favorite the API confirmed (or a listing found gone), in the order they settled (`FavoriteStore.changes`).
struct FavoriteChange: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Favorited: the card as the screen that changed it had it.
        case added(ListingSummary)
        /// No longer a favorite, or the listing is gone (`404`, deleted).
        case removed(id: String)
    }

    let seq: Int
    let kind: Kind
}
