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
/// offer) and the seller's (hide, resume, delete). The bundle toggle goes through `BundlesApi`.
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
}

extension GeneratedTaleedApi: ListingDetailApi {
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
