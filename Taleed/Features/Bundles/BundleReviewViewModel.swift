import Foundation
import Observation

/// What the bundle review screen shows below its heading (screens.md §2 G10 screen 5).
enum BundleReviewContent: Equatable {
    /// In progress, with items: the items, the summary and the actions.
    case items
    /// In progress without any item: `bundle.empty` and the way back to the shop.
    case empty
    /// Checked out: the website sends the buyer to the order; the app offers it.
    case ordered(orderId: String?)
    /// Cancelled, or a status this build does not know.
    case closed

    static func of(_ bundle: BundleDetail) -> BundleReviewContent {
        switch bundle.status {
        case .open: bundle.items.isEmpty ? .empty : .items
        case .ordered: .ordered(orderId: bundle.orderId)
        case .cancelled, .unknown: .closed
        }
    }
}

/// The bundle review screen (screens.md §2 G10 screen 5, slice C "Bundles"; website `bundle/[id]`):
/// `GET /bundles/{id}`, removing items, an offer on the bundle, a question to the seller, and checkout.
@MainActor
@Observable
final class BundleReviewViewModel {
    /// What the screen tells with a toast.
    enum Notice: Equatable {
        case error(ApiError)
        case confirmation(L10nKey)
        case information(L10nKey)
    }

    /// The answer of the offer sheet.
    enum OfferOutcome: Equatable {
        /// "Offre envoyée !", then the conversation.
        case sent(conversationId: String)
        /// An offer already waits for an answer (`offer_pending`): open its conversation.
        case pending(conversationId: String)
        /// `offer_out_of_range`: the bundle again, with its bounds (nil: no offer possible any more).
        case outOfRange(AmountRange?)
        /// Close the sheet; the toast says why.
        case failed
        /// Already sending.
        case busy
    }

    /// The request running, for its button's spinner.
    enum Work: Equatable {
        case remove(listingId: String)
        case offer
        case ask
    }

    let bundleId: String
    private(set) var bundle: BundleDetail?
    /// The first load failed (a `404`: "no longer available").
    private(set) var loadError: ApiError?
    private(set) var work: Work?
    var notice: Notice?

    @ObservationIgnored private let api: BundlesApi
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(bundleId: String, api: BundlesApi) {
        self.bundleId = bundleId
        self.api = api
    }

    var content: BundleReviewContent? { bundle.map(BundleReviewContent.of) }

    /// "Acheter le lot" or "Payer maintenant · X": checkout with the bundle and its accepted offer
    /// (the website's `/checkout/{primary}?bundle=…&offer=…`). Nil when the server does not allow buying.
    var checkout: CheckoutTarget? {
        guard let bundle, bundle.canBuy, let listingId = bundle.primaryListingId else { return nil }
        return CheckoutTarget(listingId: listingId, offerId: bundle.acceptedOffer?.id, bundleId: bundle.id)
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard bundle == nil, loadError == nil, reloadTask == nil else { return }
        await reload()
    }

    func retry() async {
        loadError = nil
        await reload()
    }

    /// Pull-to-refresh, back on the screen, back from the background (`automatic`). Joins a reload
    /// already running.
    func reload(automatic: Bool = false) async {
        if let reloadTask {
            await reloadTask.value
            return
        }
        let task = Task { await fetch(automatic: automatic) }
        reloadTask = task
        await task.value
        reloadTask = nil
    }

    private func fetch(automatic: Bool) async {
        do {
            #if DEBUG
            try debugFailFirstLoad()
            #endif
            bundle = try await api.bundleReview(id: bundleId, automatic: automatic)
            loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            if error.isNotFound {
                bundle = nil
                loadError = error
            } else if bundle == nil {
                loadError = error
            } else if !automatic {
                notice = .error(error)
            }
        }
    }

    // MARK: Actions

    /// "Retirer" would cancel the price the seller accepted on the bundle: the screen confirms first.
    var removalCancelsAcceptedOffer: Bool { bundle?.acceptedOffer != nil }

    /// "Retirer": the whole selection again without this item (`PUT`, slice C). Withdraws the bundle's
    /// offers on the server.
    func remove(_ listingId: String) async {
        guard let bundle, let username = bundle.seller.username, work == nil else { return }
        work = .remove(listingId: listingId)
        defer { work = nil }
        do {
            let saved = try await api.saveBundleSelection(sellerUsername: username, listingIds: bundle.selection(removing: listingId))
            if saved.id == bundleId {
                self.bundle = saved
            } else {
                // Another bundle is the open one now (this one was checked out meanwhile): show this one as it is.
                await reload()
            }
        } catch {
            notice = .error(error)
            if error.reloadsOfferState { await reload() }
        }
    }

    /// "Envoyer l'offre" in "Offre sur le lot".
    func makeOffer(amount: Int) async -> OfferOutcome {
        guard work == nil else { return .busy }
        work = .offer
        defer { work = nil }
        do {
            let result = try await api.makeBundleOffer(bundleId: bundleId, amount: amount)
            return .sent(conversationId: result.conversationId)
        } catch {
            switch error.code {
            case .offerPending:
                // The error names the conversation the offer waits in: open it (API 1.5.6).
                if let conversationId = error.conversationId { return .pending(conversationId: conversationId) }
                notice = .information(.offersErrorActive)
                return .failed
            case .offerOutOfRange:
                await reload()
                return .outOfRange(bundle?.canBuy == true ? bundle?.offerRange : nil)
            default:
                notice = .error(error)
                if error.reloadsOfferState { await reload() }
                return .failed
            }
        }
    }

    /// "Poser une question au vendeur": the conversation with the bundle's card, keyboard open.
    func askSeller() async -> String? {
        guard work == nil else { return nil }
        work = .ask
        defer { work = nil }
        do {
            return try await api.askAboutBundle(bundleId: bundleId)
        } catch {
            notice = .error(error)
            if error.reloadsOfferState { await reload() }
            return nil
        }
    }

    #if DEBUG
    @ObservationIgnored private var debugFailed = false

    /// `-TaleedDebugBundle offline` fails the first load (screenshots of the offline state).
    private func debugFailFirstLoad() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugBundle") == "offline", !debugFailed else { return }
        debugFailed = true
        throw .network
    }
    #endif
}
