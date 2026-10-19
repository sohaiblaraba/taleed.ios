import Foundation
import TaleedAPI

/// The seller's actions on their listing (screens.md §2 G8), on the listing screen and in My listings.
@MainActor
protocol ListingOwnerApi: AnyObject {
    /// `POST /listings/{id}/status`: hides (`HIDDEN`) or resumes (`ACTIVE`) the seller's listing.
    func setListingHidden(id: String, hidden: Bool) async throws(ApiError) -> ListingDetail
    /// `DELETE /listings/{id}`.
    func deleteListing(id: String) async throws(ApiError)
}

/// The calls of the listing screen (screens.md §2 G4): the listing, the buyer's actions (message,
/// offer, bundle toggle) and the seller's (hide, resume, delete).
@MainActor
protocol ListingDetailApi: ListingOwnerApi {
    /// `GET /listings/{id}`, never to prefetch. `countView`: true only when the member opens the screen
    /// (a view for the seller's statistics); every other reload sends `countView=false` (API 1.5.3).
    /// `automatic`: a reload the member did not ask for (return to the foreground).
    func listing(id: String, countView: Bool, automatic: Bool) async throws(ApiError) -> ListingDetail
    /// `POST /conversations {listingId}`: the buyer's conversation about the listing (created on the
    /// first call, returned after), its id.
    func openConversation(listingId: String) async throws(ApiError) -> String
    /// `POST /listings/{id}/offers {amount}`: the conversation the offer went to.
    func makeOffer(listingId: String, amount: Int) async throws(ApiError) -> String
    /// `GET /bundles/{id}`: the items of the member's open bundle.
    func bundle(id: String) async throws(ApiError) -> BundleSelectionState
    /// `PUT /members/{username}/bundle {listingIds}`: replaces the whole selection.
    func saveBundle(sellerUsername: String, listingIds: [String]) async throws(ApiError) -> BundleSelectionState
}

/// What a report is about: exactly one target (slice C, Reporting).
enum ReportTarget: Equatable, Sendable {
    case listing(id: String)
    /// The member's `id`, not the username.
    case member(id: String)
    case conversation(id: String)
}

/// `POST /reports` (slice C, Reporting), shared by the listing, the profile and the conversation.
@MainActor
protocol ReportsApi: AnyObject {
    /// `reason`: a `value` of the catalog's `reportReasons`. `evidenceKeys`: up to 3 `report_evidence` uploads.
    func report(_ target: ReportTarget, reason: String, details: String?, evidenceKeys: [String]) async throws(ApiError)
}

extension GeneratedTaleedApi: ListingDetailApi, ReportsApi {
    func listing(id: String, countView: Bool, automatic: Bool) async throws(ApiError) -> ListingDetail {
        let asOf = ContinuousClock.now
        // The parameter is left out for a counted view (its default), as the website loads the page.
        let listing = try await caller.call(.read, automatic: automatic) {
            try await ListingsAPI.getListing(id: id, countView: countView ? nil : false, apiConfiguration: $0)
        }
        return ListingDetail(listing, asOf: asOf)
    }

    func openConversation(listingId: String) async throws(ApiError) -> String {
        let request = ConversationOpen(listingId: listingId)
        // A member's action: never repeated on its own (screens.md §0.6), even though opening the same
        // conversation again returns it (slice C, Starting a conversation).
        let conversation = try await caller.call(.write) {
            try await ConversationsAPI.openConversation(conversationOpen: request, apiConfiguration: $0)
        }
        return conversation.id
    }

    func makeOffer(listingId: String, amount: Int) async throws(ApiError) -> String {
        let body = OfferAmount(amount: amount)
        // Never repeated on its own: a lost answer may have made the offer (the retry would answer
        // `offer_pending`, which opens the conversation).
        let result = try await caller.call(.write) {
            try await OffersAPI.makeListingOffer(id: listingId, offerAmount: body, apiConfiguration: $0)
        }
        return result.conversationId
    }

    func setListingHidden(id: String, hidden: Bool) async throws(ApiError) -> ListingDetail {
        let body = ListingStatusUpdate(status: hidden ? .hidden : .active)
        let asOf = ContinuousClock.now
        // Sending the status the listing already has changes nothing, but it stays a member's action.
        let listing = try await caller.call(.write) {
            try await SellingAPI.setListingStatus(id: id, listingStatusUpdate: body, apiConfiguration: $0)
        }
        return ListingDetail(listing, asOf: asOf)
    }

    func deleteListing(id: String) async throws(ApiError) {
        try await caller.call(.write) { try await SellingAPI.deleteListing(id: id, apiConfiguration: $0) }
    }

    func bundle(id: String) async throws(ApiError) -> BundleSelectionState {
        let bundle = try await caller.call(.read) { try await BundlesAPI.getBundle(id: id, apiConfiguration: $0) }
        return BundleSelectionState(bundle)
    }

    func saveBundle(sellerUsername: String, listingIds: [String]) async throws(ApiError) -> BundleSelectionState {
        let body = BundleSelection(listingIds: listingIds)
        // A member's action: never repeated on its own (screens.md §0.6). The PUT replaces the whole
        // selection, so the member's own retry is harmless (slice C, Bundles).
        let bundle = try await caller.call(.write) {
            try await BundlesAPI.saveBundle(username: sellerUsername, bundleSelection: body, apiConfiguration: $0)
        }
        return BundleSelectionState(bundle)
    }

    func report(_ target: ReportTarget, reason: String, details: String?, evidenceKeys: [String]) async throws(ApiError) {
        // The catalog value the member picked, never another category. The sheet only lists reasons
        // this build can send (`Catalog`), so this fails only on a programming error.
        guard let reportReason = ReportReason(rawValue: reason), reportReason != .unknownDefaultOpenApi else {
            let issue = ApiFieldIssue(path: "body.reason", message: "reason unknown to this build")
            throw .failed(ApiFailure(status: 400, code: .invalidRequest, issues: [issue]))
        }
        let request = ReportCreate(target, reason: reportReason, details: details, evidenceKeys: evidenceKeys)
        // A repeat after a lost answer says `already_reported`, which the sheet treats as sent.
        try await caller.call(.write) { try await SafetyAPI.createReport(reportCreate: request, apiConfiguration: $0) }
    }
}

// MARK: - Mapping

extension ListingDetail {
    /// From the API's listing. Unknown enum values become "no tag" and `.unknown` (api-guide.md,
    /// Compatibility). `asOf`: when the request started.
    init(_ listing: TaleedAPI.ListingDetail, asOf: ContinuousClock.Instant = .now) {
        self.init(
            id: listing.id,
            title: listing.title,
            description: listing.description,
            price: listing.price,
            protectionFee: listing.protectionFee,
            size: listing.size.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
            brand: listing.brand.flatMap {
                $0.name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ListingBrandRef(slug: $0.slug, name: $0.name)
            },
            condition: listing.condition == .unknownDefaultOpenApi ? nil : listing.condition.rawValue,
            status: listing.status == .unknownDefaultOpenApi ? .unknown : ListingStatus(code: listing.status.rawValue),
            photos: listing.photos.map {
                ListingPhoto(id: $0.id, url: URL(string: $0.url), thumbURL: URL(string: $0.thumbUrl))
            },
            category: ListingCategoryRef(slug: listing.category.slug, name: listing.category.name,
                                         parentName: listing.category.parent?.name, id: listing.category.id,
                                         parentId: listing.category.parent?.id),
            shipsFrom: listing.shipsFrom.map { CatalogWilaya(id: $0.id, name: $0.name) },
            viewsCount: listing.viewsCount,
            favoritesCount: listing.favoritesCount,
            isFavorited: listing.isFavorited,
            isBoosted: listing.isBoosted,
            isOwner: listing.isOwner,
            seller: ListingSellerInfo(listing.seller),
            acceptedOffer: listing.acceptedOffer.map { AcceptedOfferRef(id: $0.id, amount: $0.amount) },
            canBuy: listing.canBuy,
            orderId: listing.orderId,
            offerRange: listing.offerRange.map { AmountRange(min: $0.min, max: $0.max) },
            canMessage: listing.canMessage,
            canBundle: listing.canBundle,
            openBundleId: listing.openBundleId,
            inMyBundle: listing.inMyBundle,
            memberItems: listing.memberItems.map { ListingSummary($0, asOf: asOf) },
            similar: listing.similar.map { ListingSummary($0, asOf: asOf) },
            shareURL: URL(string: listing.shareUrl),
            createdAt: listing.createdAt,
            asOf: asOf
        )
    }
}

private extension ListingSellerInfo {
    init(_ seller: TaleedAPI.ListingSeller) {
        self.init(
            id: seller.id,
            username: seller.username,
            displayName: seller.displayName,
            avatarURL: seller.avatarUrl.flatMap(URL.init(string:)),
            isVerified: seller.isVerified,
            isOfficial: seller.isOfficial,
            rating: seller.rating.flatMap { $0.count >= 1 ? MemberRating(average: $0.average, count: $0.count) : nil },
            lastSeenAt: seller.lastSeenAt,
            isOnline: seller.isOnline
        )
    }
}

private extension BundleSelectionState {
    init(_ bundle: BundleReview) {
        self.init(id: bundle.id, listingIds: bundle.items.map(\.listingId))
    }
}

private extension ReportCreate {
    init(_ target: ReportTarget, reason: ReportReason, details: String?, evidenceKeys: [String]) {
        var listingId: String?
        var memberId: String?
        var conversationId: String?
        switch target {
        case let .listing(id): listingId = id
        case let .member(id): memberId = id
        case let .conversation(id): conversationId = id
        }
        self.init(
            listingId: listingId, memberId: memberId, conversationId: conversationId,
            reason: reason,
            details: details, evidenceKeys: evidenceKeys.isEmpty ? nil : evidenceKeys
        )
    }
}
