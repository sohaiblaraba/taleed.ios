import Foundation
import Observation

/// The listing screen (screens.md §2 G4): loads `GET /listings/{id}` when the member opens it (it counts
/// a view), keeps it while the screen is in the stack, and runs the buyer's and the seller's actions.
///
/// Actions return what happened; the screen shows the toast and navigates. The view model never
/// decides a permission itself: `ListingDetailActions` reads the server's flags.
@MainActor
@Observable
final class ListingDetailViewModel {
    /// What a buyer started signed out, run once signed in when the reloaded listing still allows it
    /// (screens.md §0.5: return to the action started).
    enum PendingAction: Equatable, Sendable {
        case buy, makeOffer, message, report, shopBundles, toggleBundle
    }

    /// The answer of an action, for the screen to act on.
    enum Outcome: Equatable {
        /// Done; the listing on screen is up to date.
        case done
        /// Open this conversation.
        case openConversation(String)
        /// The listing was deleted (or was already gone): leave the screen.
        case deleted
        /// It failed: show the message. The listing was reloaded when the error says it changed.
        case failed(ApiError)
    }

    /// The answer of the offer sheet.
    enum OfferOutcome: Equatable {
        /// Sent: "Offre envoyée !", then the conversation.
        case sent(conversationId: String)
        /// An offer already waits in that conversation (`offer_pending`): open it.
        case pending(conversationId: String)
        /// `offer_out_of_range`: the price changed. The sheet shows the new bounds (nil: no offer possible).
        case outOfRange(AmountRange?)
        /// Close the sheet and show the message (the listing was reloaded when it changed).
        case failed(ApiError)
        /// An offer is already being sent: nothing to do.
        case busy
    }

    /// Requests running, to disable their buttons.
    enum Work: Hashable, Sendable {
        case message, offer, visibility, delete, bundle
    }

    let listingId: String
    private(set) var listing: ListingDetail?
    /// The first load failed (`404`: "no longer available").
    private(set) var loadError: ApiError?
    /// A reload the member asked for failed while the listing stays on screen: a toast.
    private(set) var refreshError: ApiError?
    private(set) var running: Set<Work> = []
    /// The member's open bundle with this seller, for "Retour à la boutique · N articles".
    private(set) var bundle: BundleSelectionState?

    @ObservationIgnored private let api: ListingDetailApi
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    /// The member the listing on screen was loaded for (nil signed out): its flags are theirs.
    @ObservationIgnored private var loadedFor: String??
    @ObservationIgnored private var memberId: String?
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?

    /// A shorter absence keeps the listing as it is (as Home and search).
    static let foregroundReloadAfter: Duration = .seconds(60)

    init(listingId: String, api: ListingDetailApi, memberId: String? = nil) {
        self.listingId = listingId
        self.api = api
        self.memberId = memberId
    }

    var isLoading: Bool { listing == nil && loadError == nil }

    func actions(isSignedIn: Bool) -> ListingDetailActions? {
        listing.map { ListingDetailActions(listing: $0, isSignedIn: isSignedIn) }
    }

    func isRunning(_ work: Work) -> Bool { running.contains(work) }

    // MARK: Loading

    /// The first load, once.
    func loadIfNeeded() async {
        guard listing == nil, loadError == nil, reloadTask == nil else { return }
        await reload()
    }

    /// "Retry" after a failed first load.
    func retry() async {
        loadError = nil
        await reload()
    }

    /// Pull-to-refresh, after an action, after signing in. Joins a reload already running.
    /// - Parameter automatic: the member did not ask for it (foreground): paused during a `429`.
    func reload(automatic: Bool = false) async {
        if let reloadTask {
            await reloadTask.value
            return
        }
        let task = Task { await self.fetch(automatic: automatic) }
        reloadTask = task
        await task.value
        reloadTask = nil
    }

    private func fetch(automatic: Bool) async {
        let member = memberId
        do {
            #if DEBUG
            try debugFailFirstLoad()
            #endif
            let fresh = try await api.listing(id: listingId, automatic: automatic)
            listing = fresh
            loadError = nil
            refreshError = nil
            loadedFor = .some(member)
            await loadBundle(of: fresh)
        } catch {
            if error.isNotFound {
                // Removed, hidden or taken down: "no longer available", even over a listing on screen.
                listing = nil
                loadError = error
            } else if listing == nil {
                loadError = error
            } else if !automatic {
                refreshError = error
            }
        }
    }

    /// The items of the member's open bundle with this seller. Without it, the toggle still works (it
    /// fetches the bundle first); only the count is missing.
    private func loadBundle(of listing: ListingDetail) async {
        guard let bundleId = listing.openBundleId, !listing.isOwner else {
            bundle = nil
            return
        }
        guard bundle?.id != bundleId else { return }
        bundle = try? await api.bundle(id: bundleId)
    }

    /// Another member signed in or out: the flags (owner, accepted offer, bundle) are theirs now.
    func memberDidChange(to memberId: String?) async {
        guard memberId != self.memberId else { return }
        self.memberId = memberId
        bundle = nil
        guard listing != nil || loadError != nil else { return }
        await reload()
    }

    /// Signed in from a button: the listing again for this member, then the action if it is still offered.
    func resolvePending(_ action: PendingAction, memberId: String?) async -> PendingAction? {
        if memberId != self.memberId {
            self.memberId = memberId
            bundle = nil
        }
        if loadedFor != .some(memberId) || reloadTask != nil {
            await reload()
        }
        guard let actions = actions(isSignedIn: memberId != nil) else { return nil }
        let allowed = switch action {
        case .buy: actions.buy != nil
        case .makeOffer: actions.showsMakeOffer
        case .message: actions.showsMessage
        case .report: actions.showsReport
        case .shopBundles: actions.showsShopBundles
        case .toggleBundle: actions.bundleToggle != nil
        }
        return allowed ? action : nil
    }

    func wentToBackground(at instant: ContinuousClock.Instant = .now) {
        backgroundSince = instant
    }

    /// Back after a while (screens.md §0.6): the listing again, quietly.
    func returnedToForeground(at instant: ContinuousClock.Instant = .now) async {
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        guard instant - since >= Self.foregroundReloadAfter, listing != nil else { return }
        await reload(automatic: true)
    }

    // MARK: Buyer

    /// "Envoyer un message": the conversation about this listing (slice C, Starting a conversation).
    func messageSeller() async -> Outcome {
        guard begin(.message) else { return .done }
        defer { end(.message) }
        do {
            return .openConversation(try await api.openConversation(listingId: listingId))
        } catch {
            return await failure(error)
        }
    }

    /// "Envoyer l'offre" (slice C, Offers): the amount was checked against `offerRange` by the sheet.
    func makeOffer(amount: Int) async -> OfferOutcome {
        guard begin(.offer) else { return .busy }
        defer { end(.offer) }
        do {
            let conversationId = try await api.makeOffer(listingId: listingId, amount: amount)
            return .sent(conversationId: conversationId)
        } catch {
            switch error.code {
            case .offerPending:
                // The conversation holds the offer waiting for an answer: open it.
                do {
                    return .pending(conversationId: try await api.openConversation(listingId: listingId))
                } catch {
                    return .failed(error)
                }
            case .offerOutOfRange:
                await reload()
                let stillOffered = listing.map { ListingDetailActions(listing: $0, isSignedIn: true).showsMakeOffer } ?? false
                return .outOfRange(stillOffered ? listing?.offerRange : nil)
            default:
                _ = await failure(error)
                return .failed(error)
            }
        }
    }

    /// "Ajouter au lot" / "Retirer du lot": the whole selection with this item added or removed
    /// (slice F, The bundle toggle).
    func toggleBundle() async -> Outcome {
        guard let listing, let username = listing.seller.username, begin(.bundle) else { return .done }
        defer { end(.bundle) }
        do {
            var current: [String] = []
            if let bundleId = listing.openBundleId {
                let fetched = bundle?.id == bundleId ? bundle : try await api.bundle(id: bundleId)
                current = fetched?.listingIds ?? []
            }
            let ids = listing.inMyBundle || current.contains(listingId)
                ? current.filter { $0 != listingId }
                : current + [listingId]
            let saved = try await api.saveBundle(sellerUsername: username, listingIds: ids)
            bundle = saved
            self.listing?.openBundleId = saved.id
            self.listing?.inMyBundle = saved.listingIds.contains(listingId)
            return .done
        } catch {
            return await failure(error)
        }
    }

    // MARK: Seller

    /// "Masquer" or "Remettre en vente", without confirmation (screens.md §7 G4).
    func setHidden(_ hidden: Bool) async -> Outcome {
        guard begin(.visibility) else { return .done }
        defer { end(.visibility) }
        do {
            listing = try await api.setListingHidden(id: listingId, hidden: hidden)
            return .done
        } catch {
            return await failure(error)
        }
    }

    /// "Supprimer" after the confirmation. A `404` means it is already gone: done (slice B, Deleting).
    func delete() async -> Outcome {
        guard begin(.delete) else { return .done }
        defer { end(.delete) }
        do {
            try await api.deleteListing(id: listingId)
            return .deleted
        } catch {
            if error.isNotFound { return .deleted }
            return await failure(error)
        }
    }

    #if DEBUG
    @ObservationIgnored private var debugFailed = false

    /// `-TaleedDebugListing offline` fails the first load (screenshots of the offline state).
    private func debugFailFirstLoad() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugListing") == "offline", !debugFailed else { return }
        debugFailed = true
        throw .network
    }
    #endif

    // MARK: Errors

    /// Reloads when the error says the listing or the relation changed (slices B and C), then hands the
    /// error to the screen.
    private func failure(_ error: ApiError) async -> Outcome {
        switch error.code {
        case .notFound, .listingLocked, .listingUnavailable, .blocked, .forbidden, .offerClosed, .conversationReadOnly:
            await reload()
        default:
            break
        }
        return .failed(error)
    }

    private func begin(_ work: Work) -> Bool {
        guard !running.contains(work) else { return false }
        running.insert(work)
        return true
    }

    private func end(_ work: Work) {
        running.remove(work)
    }
}
