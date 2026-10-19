import Foundation
import Observation

/// The hearts of every listing card and listing screen (slice B, Favorites), so that a heart tapped
/// on one screen shows on the others without a reload.
///
/// A tap fills or empties the heart at once and moves the count; the API's answer then sets both.
/// Taps made while a request runs are kept: once it answers, the store sends what the member asked
/// for last. On a failure the heart goes back to the last state the API confirmed. `404 not_found`
/// (the listing was deleted, taken down or hidden) puts the id in `removedIds`: lists leave the card out.
@MainActor
@Observable
final class FavoriteStore {
    /// What the member changed in this session, by listing id. Wins over the state a card came with.
    private(set) var overrides: [String: FavoriteState] = [:]
    /// Listings that answered `404`.
    private(set) var removedIds: Set<String> = []

    /// A favorite could not be changed (not a `404`): the app's toast.
    @ObservationIgnored var onFailure: ((ApiError) -> Void)?
    /// A favorite answered `404`: "no longer available".
    @ObservationIgnored var onRemoved: ((String) -> Void)?

    @ObservationIgnored private let api: FavoritesApi
    /// The state the API last confirmed, by listing id (the card's state before the first tap).
    @ObservationIgnored private var confirmed: [String: FavoriteState] = [:]
    /// What the member asked for last, while a request for that listing runs.
    @ObservationIgnored private var wanted: [String: Bool] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []

    init(api: FavoritesApi) {
        self.api = api
    }

    /// The heart and count to draw for a listing.
    func state(for listing: ListingSummary) -> FavoriteState {
        overrides[listing.id] ?? FavoriteState(isFavorited: listing.isFavorited, count: listing.favoritesCount)
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
        if confirmed[id] == nil { confirmed[id] = current }
        wanted[id] = favorited
        if current.isFavorited != favorited {
            overrides[id] = FavoriteState(isFavorited: favorited, count: max(0, current.count + (favorited ? 1 : -1)))
        }
        // Sent even when the heart already shows that state (after a sign-in): both calls are idempotent.
        guard !inFlight.contains(id) else { return nil }
        inFlight.insert(id)
        return Task { await send(id) }
    }

    /// The session changed (sign-in, sign-out, another account): the lists reload with the new
    /// member's hearts, so the changes of the previous one no longer apply. Requests still running
    /// keep their answer.
    func sessionDidChange() {
        overrides = overrides.filter { inFlight.contains($0.key) }
        confirmed = confirmed.filter { inFlight.contains($0.key) }
    }

    private func send(_ id: String) async {
        guard let favorited = wanted[id] else {
            inFlight.remove(id)
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
            overrides[id] = answer
            wanted[id] = nil
            inFlight.remove(id)
        } catch {
            inFlight.remove(id)
            wanted[id] = nil
            if let last = confirmed[id] { overrides[id] = last }
            if error.isNotFound {
                removedIds.insert(id)
                onRemoved?(id)
            } else {
                onFailure?(error)
            }
        }
    }
}
