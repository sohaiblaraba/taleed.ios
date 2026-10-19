import SwiftUI
import TaleedAPI

/// A buyer's bundle with one seller, as the review screen shows it (`BundleReview`, slice C "Bundles").
/// Every amount comes from the server (screens.md §0.1): the app adds nothing up.
struct BundleDetail: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// In progress: the buyer can still change it, offer on it, buy it.
        case open
        /// Checked out: `orderId` is the order.
        case ordered
        case cancelled
        /// A status added after this build: shown like a bundle no longer in progress.
        case unknown
    }

    let id: String
    let status: Status
    let seller: ChatMember
    /// In the buyer's order. Items no longer for sale are greyed out and left out of the totals.
    let items: [BundleLine]
    let unavailableCount: Int
    /// The items still for sale, added up. Offers on the bundle are bounded on it.
    let subtotal: Int
    /// An offer on the bundle the seller accepted, not used by an order yet: its amount replaces `subtotal`.
    let acceptedOffer: AcceptedOfferRef?
    /// What the items cost: the accepted offer, or `subtotal`.
    let itemsTotal: Int
    let protectionFee: Int
    /// Nil: "calculée au paiement".
    let shippingFrom: Int?
    /// An estimate of what checkout charges.
    let total: Int
    /// Nil when no offer can be made.
    let offerRange: AmountRange?
    /// "Acheter le lot", "Faire une offre" and "Poser une question au vendeur".
    let canBuy: Bool
    let orderId: String?

    var listingIds: [String] { items.map(\.listingId) }
    var availableItems: [BundleLine] { items.filter(\.isAvailable) }

    /// The item checkout and the conversation are about: the first one still for sale (the website's
    /// `primaryListingId`).
    var primaryListingId: String? { (availableItems.first ?? items.first)?.listingId }

    /// The items a change starts from. `PUT /members/{username}/bundle` replaces the whole selection
    /// (slice C, Bundles), so every change sends all of it: the open bundle's items in the buyer's order,
    /// none once it was checked out or cancelled (the next change opens a new bundle).
    var selection: [String] { status == .open ? listingIds : [] }

    /// The whole selection to send without this item ("Retirer", "Retirer du lot").
    func selection(removing listingId: String) -> [String] {
        selection.filter { $0 != listingId }
    }

    /// The whole selection to send with this item at the end ("Ajouter au lot").
    func selection(adding listingId: String) -> [String] {
        selection.contains(listingId) ? selection : selection + [listingId]
    }
}

/// An item of a bundle (`BundleItem`).
struct BundleLine: Identifiable, Equatable, Sendable {
    let listingId: String
    let title: String
    /// The price when it was added to the bundle.
    let price: Int
    let imageURL: URL?
    let isAvailable: Bool

    var id: String { listingId }
}

/// The calls of the bundle screens (screens.md §2 G10, slice C "Bundles"). The seller's wardrobe and
/// profile come from `MembersApi`.
@MainActor
protocol BundlesApi: AnyObject {
    /// `GET /bundles/{id}`: only the bundle's buyer can open it.
    func bundleReview(id: String, automatic: Bool) async throws(ApiError) -> BundleDetail
    /// `PUT /members/{username}/bundle {listingIds}`: replaces the whole selection, 20 items at most, in
    /// the order the buyer picked them; `[]` clears it. Changing the items withdraws the bundle's offers.
    func saveBundleSelection(sellerUsername: String, listingIds: [String]) async throws(ApiError) -> BundleDetail
    /// `POST /bundles/{id}/offers {amount}`: one price for every item still for sale.
    func makeBundleOffer(bundleId: String, amount: Int) async throws(ApiError) -> OfferActionResult
    /// `POST /bundles/{id}/ask`: posts the bundle's card to the seller (once) and answers the conversation's id.
    func askAboutBundle(bundleId: String) async throws(ApiError) -> String
}

extension GeneratedTaleedApi: BundlesApi {
    func bundleReview(id: String, automatic: Bool) async throws(ApiError) -> BundleDetail {
        let bundle = try await caller.call(.read, automatic: automatic) {
            try await BundlesAPI.getBundle(id: id, apiConfiguration: $0)
        }
        return BundleDetail(bundle)
    }

    func saveBundleSelection(sellerUsername: String, listingIds: [String]) async throws(ApiError) -> BundleDetail {
        let body = BundleSelection(listingIds: listingIds)
        // A member's action: never repeated on its own (screens.md §0.6); the member's own retry is
        // harmless, the PUT replacing the whole selection (slice C, Retrying).
        let bundle = try await caller.call(.write) {
            try await BundlesAPI.saveBundle(username: sellerUsername, bundleSelection: body, apiConfiguration: $0)
        }
        return BundleDetail(bundle)
    }

    func makeBundleOffer(bundleId: String, amount: Int) async throws(ApiError) -> OfferActionResult {
        let body = OfferAmount(amount: amount)
        // A repeat after a lost answer says `offer_pending` (slice C, Retrying).
        let result = try await caller.call(.write) {
            try await BundlesAPI.makeBundleOffer(id: bundleId, offerAmount: body, apiConfiguration: $0)
        }
        return OfferActionResult(result)
    }

    func askAboutBundle(bundleId: String) async throws(ApiError) -> String {
        // Idempotent (asking again posts no second card), but still the member's tap.
        let conversation = try await caller.call(.write) {
            try await BundlesAPI.askAboutBundle(id: bundleId, apiConfiguration: $0)
        }
        return conversation.id
    }
}

/// What the bundle screens need. Set once at the root (`AppRootView`).
struct BundleDependencies {
    let bundles: any BundlesApi
    let members: any MembersApi
}

private struct BundleDependenciesKey: EnvironmentKey {
    static var defaultValue: BundleDependencies? { nil }
}

extension EnvironmentValues {
    var bundleDependencies: BundleDependencies? {
        get { self[BundleDependenciesKey.self] }
        set { self[BundleDependenciesKey.self] = newValue }
    }
}

// MARK: - Mapping

extension BundleDetail {
    init(_ bundle: BundleReview) {
        let status: Status = switch bundle.status {
        case ._open: .open
        case .ordered: .ordered
        case .cancelled: .cancelled
        case .unknownDefaultOpenApi: .unknown
        }
        self.init(
            id: bundle.id,
            status: status,
            seller: ChatMember(bundle.seller),
            items: bundle.items.map {
                BundleLine(listingId: $0.listingId, title: $0.title, price: $0.price, imageURL: URL(apiString: $0.imageUrl),
                           isAvailable: $0.isAvailable)
            },
            unavailableCount: bundle.unavailableCount,
            subtotal: bundle.subtotal,
            acceptedOffer: bundle.acceptedOffer.map { AcceptedOfferRef(id: $0.id, amount: $0.amount) },
            itemsTotal: bundle.itemsTotal,
            protectionFee: bundle.protectionFee,
            shippingFrom: bundle.shippingFrom,
            total: bundle.total,
            offerRange: bundle.offerRange.map { AmountRange(min: $0.min, max: $0.max) },
            canBuy: bundle.canBuy,
            orderId: bundle.orderId
        )
    }
}
