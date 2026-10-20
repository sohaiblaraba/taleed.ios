import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// MARK: - Fixtures

extension Taleed.ListingDetail {
    static func fixture(
        id: String = "l1", price: Int = 2500, status: Taleed.ListingStatus = .active, isOwner: Bool = false,
        acceptedOffer: AcceptedOfferRef? = nil, canBuy: Bool = true, orderId: String? = nil,
        offerRange: AmountRange? = AmountRange(min: 750, max: 2500), canMessage: Bool = true, canBundle: Bool = true,
        openBundleId: String? = nil, inMyBundle: Bool = false, username: String? = "amina"
    ) -> Taleed.ListingDetail {
        Taleed.ListingDetail(
            id: id, title: "Robe fleurie Zara", description: "Robe légère", price: price, protectionFee: 175, size: "S",
            brand: ListingBrandRef(slug: "zara", name: "Zara"), condition: "VERY_GOOD", status: status,
            photos: [ListingPhoto(id: "p1", url: nil, thumbURL: nil)],
            category: ListingCategoryRef(slug: "women-clothes", name: "Vêtements", parentName: "Femmes"),
            shipsFrom: CatalogWilaya(id: 16, name: "Alger"), viewsCount: 5, favoritesCount: 4, isFavorited: false,
            isBoosted: false, isOwner: isOwner,
            seller: ListingSellerInfo(id: "s1", username: username, displayName: "@amina", avatarURL: nil, isVerified: false,
                                      isOfficial: false, rating: nil, lastSeenAt: nil, isOnline: true),
            acceptedOffer: acceptedOffer, canBuy: canBuy, orderId: orderId, offerRange: offerRange, canMessage: canMessage,
            canBundle: canBundle, openBundleId: openBundleId, inMyBundle: inMyBundle, memberItems: [], similar: [],
            shareURL: URL(string: "https://taleed.app/listings/\(id)"), createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}

func apiError(_ status: Int, _ code: String) -> Taleed.ApiError {
    .from(status: status, body: Data(#"{"error":{"code":"\#(code)","message":"x"}}"#.utf8))
}

/// A `ListingDetailApi` and `ReportsApi` answering from canned results.
@MainActor
final class FakeListingDetailApi: ListingDetailApi, ReportsApi {
    var listings: [Result<Taleed.ListingDetail, Taleed.ApiError>] = []
    var listing: Result<Taleed.ListingDetail, Taleed.ApiError> = .success(.fixture())
    var conversation: Result<String, Taleed.ApiError> = .success("cnv1")
    var offer: Result<String, Taleed.ApiError> = .success("cnv1")
    var visibility: Result<Taleed.ListingDetail, Taleed.ApiError>?
    var deletion: Result<Void, Taleed.ApiError> = .success(())
    var report: Result<Void, Taleed.ApiError> = .success(())
    /// Each `GET /listings/{id}`: whether it counted a view, whether the member asked for it.
    struct ListingCall: Equatable {
        let countView: Bool
        let automatic: Bool
    }

    private(set) var listingCalls: [ListingCall] = []
    private(set) var offers: [Int] = []
    struct SentReport {
        let target: ReportTarget
        let reason: String
        let details: String?
        let evidenceKeys: [String]
    }

    private(set) var reports: [SentReport] = []

    func listing(id: String, countView: Bool, automatic: Bool) async throws(Taleed.ApiError) -> Taleed.ListingDetail {
        listingCalls.append(ListingCall(countView: countView, automatic: automatic))
        if !listings.isEmpty { return try listings.removeFirst().get() }
        return try listing.get()
    }

    func openConversation(listingId: String) async throws(Taleed.ApiError) -> String { try conversation.get() }

    func makeOffer(listingId: String, amount: Int) async throws(Taleed.ApiError) -> String {
        offers.append(amount)
        return try offer.get()
    }

    func setListingHidden(id: String, hidden: Bool) async throws(Taleed.ApiError) -> Taleed.ListingDetail {
        try (visibility ?? .success(.fixture(status: hidden ? .hidden : .active, isOwner: true))).get()
    }

    func deleteListing(id: String) async throws(Taleed.ApiError) { try deletion.get() }

    func report(_ target: ReportTarget, reason: String, details: String?, evidenceKeys: [String]) async throws(Taleed.ApiError) {
        reports.append(SentReport(target: target, reason: reason, details: details, evidenceKeys: evidenceKeys))
        try report.get()
    }
}

// MARK: - Buttons by state

struct ListingDetailActionsTests {
    @Test func aBuyerSignedOutSeesEveryButtonAndNoOwnerBar() {
        let actions = ListingDetailActions(listing: .fixture(), isSignedIn: false)
        #expect(actions.buy == .buy)
        #expect(actions.showsMakeOffer)
        #expect(actions.showsMessage)
        #expect(actions.showsReport)
        #expect(actions.showsShopBundles)
        #expect(actions.owner == nil)
        #expect(actions.banner == nil)
        #expect(actions.bundleToggle == nil)
        #expect(actions.hasBottomBar)
    }

    @Test func anAcceptedOfferBecomesPayNowWithItsAmount() {
        let listing = Taleed.ListingDetail.fixture(acceptedOffer: AcceptedOfferRef(id: "o1", amount: 2000))
        let actions = ListingDetailActions(listing: listing, isSignedIn: true)
        #expect(actions.buy == .payNow(offerId: "o1", amount: 2000))
        #expect(actions.buy?.offerId == "o1")
        #expect(actions.acceptedOfferAmount == 2000)
    }

    @Test func theOwnerGetsOnlyTheOwnerActionsOfTheStatusTable() {
        let active = ListingDetailActions(listing: .fixture(isOwner: true), isSignedIn: true)
        #expect(active.owner == .init(canEdit: true, visibility: .hide, canDelete: true))
        #expect(active.buy == nil && !active.showsMakeOffer && !active.showsMessage && !active.showsReport && !active.showsShopBundles)
        #expect(!active.hasBottomBar)
        #expect(ListingDetailActions.OwnerActions(status: .hidden) == .init(canEdit: true, visibility: .resume, canDelete: true))
        #expect(ListingDetailActions.OwnerActions(status: .reserved) == .init(canEdit: false, visibility: nil, canDelete: false))
        #expect(ListingDetailActions.OwnerActions(status: .sold) == .init(canEdit: false, visibility: nil, canDelete: true))
        #expect(ListingDetailActions.OwnerActions(status: .unknown) == .init(canEdit: false, visibility: nil, canDelete: false))
        #expect(ListingDetailActions.OwnerActions(status: .draft) == .init(canEdit: false, visibility: nil, canDelete: false))
    }

    @Test func aSoldListingShowsTheBannerAndTheOrderButNoBuyButtons() {
        let listing = Taleed.ListingDetail.fixture(status: .sold, canBuy: true, orderId: "ord1")
        let actions = ListingDetailActions(listing: listing, isSignedIn: true)
        #expect(actions.banner == .sold)
        #expect(actions.showsViewOrder)
        #expect(actions.buy == nil)
        #expect(!actions.showsMakeOffer)
        #expect(actions.hasBottomBar)
        #expect(ListingDetailActions(listing: .fixture(status: .reserved), isSignedIn: true).banner == .reserved)
        #expect(ListingDetailActions(listing: .fixture(status: .hidden, isOwner: true), isSignedIn: true).banner == .hidden)
        #expect(ListingDetailActions(listing: .fixture(status: .unknown), isSignedIn: true).buy == nil)
    }

    @Test func theFlagsDecideNotTheDevice() {
        let listing = Taleed.ListingDetail.fixture(canBuy: false, offerRange: nil, canMessage: false, canBundle: false)
        let actions = ListingDetailActions(listing: listing, isSignedIn: true)
        #expect(actions.buy == nil && !actions.showsMakeOffer && !actions.showsMessage && !actions.showsShopBundles)
        #expect(!actions.hasBottomBar)
    }

    @Test func theBundleToggleShowsWhileTheMemberBuildsABundle() {
        let inBundle = Taleed.ListingDetail.fixture(openBundleId: "b1", inMyBundle: true)
        #expect(ListingDetailActions(listing: inBundle, isSignedIn: true).bundleToggle == .remove)
        #expect(ListingDetailActions(listing: .fixture(openBundleId: "b1"), isSignedIn: true).bundleToggle == .add)
        #expect(ListingDetailActions(listing: .fixture(openBundleId: nil), isSignedIn: true).bundleToggle == nil)
        #expect(ListingDetailActions(listing: inBundle, isSignedIn: false).bundleToggle == nil)
        #expect(ListingDetailActions(listing: .fixture(openBundleId: "b1", username: nil), isSignedIn: true).bundleToggle == nil)
    }
}

// MARK: - Offer amount, times, rating

struct ListingDetailFormattingTests {
    private let range = AmountRange(min: 750, max: 2500)

    @Test func theOfferAmountIsCheckedAgainstTheServersBounds() {
        #expect(OfferAmountInput(text: "", range: range) == .empty)
        #expect(OfferAmountInput(text: "abc", range: range) == .empty)
        #expect(OfferAmountInput(text: "749", range: range) == .outOfRange)
        #expect(OfferAmountInput(text: "750", range: range) == .valid(750))
        #expect(OfferAmountInput(text: "2 500", range: range) == .valid(2500))
        #expect(OfferAmountInput(text: "2501", range: range) == .outOfRange)
        #expect(OfferAmountInput(text: "99999999999999", range: range) == .outOfRange)
    }

    @Test func arabicIndicDigitsReadAsWesternDigits() {
        #expect(OfferAmountInput.normalizedDigits("٢٠٠٠") == "2000")
        #expect(OfferAmountInput.normalizedDigits("۱۵۰۰ DA") == "1500")
        #expect(OfferAmountInput(text: "١٠٠٠", range: range) == .valid(1000))
    }

    @Test func relativeTimesFollowTheWebsitesUnits() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let english = Locale(identifier: "en")
        #expect(RelativeTimeText.string(for: now.addingTimeInterval(-5 * 60), now: now, locale: english) == "5 minutes ago")
        #expect(RelativeTimeText.string(for: now.addingTimeInterval(-3 * 3600), now: now, locale: english) == "3 hours ago")
        #expect(RelativeTimeText.string(for: now.addingTimeInterval(-86400), now: now, locale: english) == "yesterday")
        #expect(RelativeTimeText.string(for: now.addingTimeInterval(-3 * 86400), now: now, locale: english) == "3 days ago")
        #expect(RelativeTimeText.string(for: now.addingTimeInterval(-60 * 86400), now: now, locale: english) == "2 months ago")
        let french = Locale(identifier: "fr")
        #expect(RelativeTimeText.string(for: now.addingTimeInterval(-3 * 3600), now: now, locale: french) == "il y a 3 heures")
    }

    @Test func arabicTimesUseLatinDigits() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let text = RelativeTimeText.string(for: now.addingTimeInterval(-5 * 86400), now: now,
                                           locale: AppLanguage.ar.formattingLocale)
        #expect(text.contains("5"))
    }

    @Test func theRatingHasOneDecimalInLatinDigits() {
        #expect(RatingText.average(5) == "5.0")
        #expect(RatingText.average(4.84) == "4.8")
    }

    @Test func theBundleCountHasItsZeroWording() {
        let french = Locale(identifier: "fr")
        #expect(DesignSystemStrings.format(.bundleBackToBundle, locale: french, 0) == "Retour à la boutique")
        #expect(DesignSystemStrings.format(.bundleBackToBundle, locale: french, 2) == "Retour à la boutique · 2 articles")
        #expect(DesignSystemStrings.format(.listingViews, locale: french, 1) == "1 vue")
        #expect(DesignSystemStrings.format(.listingViews, locale: Locale(identifier: "en"), 34) == "34 views")
    }

    @Test func everyListingKeyHasTheThreeLanguages() {
        let keys: [L10nKey] = [.appListingTitle, .listingProtectionFeeNote, .offersErrorRange, .reportSent, .appListingAcceptedOffer]
        for key in keys {
            for language in AppLanguage.allCases {
                let value = DesignSystemStrings.string(key, language: language)
                #expect(value != key.rawValue, "\(key.rawValue) in \(language.rawValue)")
            }
        }
    }
}

// MARK: - Mapping

struct ListingDetailMappingTests {
    private func detail(condition: TaleedAPI.ListingCondition = .veryGood, status: TaleedAPI.ListingStatus = .active,
                        brand: ListingBrand? = ListingBrand(slug: nil, name: "Ma marque"),
                        rating: Rating? = Rating(average: 4.5, count: 0)) -> TaleedAPI.ListingDetail {
        TaleedAPI.ListingDetail(
            id: "l1", title: "Robe", description: "", price: 2500, protectionFee: 175, size: " ", brand: brand,
            condition: condition, status: status, photos: [Photo(id: "p", url: "https://e.com/a.jpg", thumbUrl: "https://e.com/t.jpg")],
            category: ListingCategory(id: "c", slug: "women-clothes", name: "Vêtements",
                                      parent: CategoryRef(id: "p", slug: "women", name: "Femmes")),
            shipsFrom: nil, viewsCount: 1, favoritesCount: 0, isFavorited: false, isBoosted: false, isOwner: false,
            seller: ListingSeller(id: "s", username: "amina", displayName: "@amina", avatarUrl: nil, isVerified: false, isOfficial: false,
                                  rating: rating, lastSeenAt: nil, isOnline: false),
            acceptedOffer: nil, canBuy: true, orderId: nil, offerRange: OfferRange(min: 750, max: 2500), canMessage: true,
            canBundle: false, openBundleId: nil, inMyBundle: false, memberItems: [], similar: [],
            shareUrl: "https://taleed.app/listings/l1", createdAt: Date(), updatedAt: Date()
        )
    }

    @Test func knownValuesMapAndUnknownOnesAreTolerated() {
        let known = Taleed.ListingDetail(detail())
        #expect(known.condition == "VERY_GOOD")
        #expect(known.status == .active)
        #expect(known.brand == ListingBrandRef(slug: nil, name: "Ma marque"))
        #expect(known.size == nil)
        #expect(known.seller.rating == nil)
        #expect(known.category.parentName == "Femmes")
        #expect(known.offerRange == AmountRange(min: 750, max: 2500))
        #expect(known.photos.first?.thumbURL == URL(string: "https://e.com/t.jpg"))
        let unknown = Taleed.ListingDetail(detail(condition: .unknownDefaultOpenApi, status: .unknownDefaultOpenApi))
        #expect(unknown.condition == nil)
        #expect(unknown.status == .unknown)
    }
}

// MARK: - View model

@MainActor
struct ListingDetailViewModelTests {
    private let api = FakeListingDetailApi()
    private let bundles = FakeBundlesApi()

    @Test func aMissingListingShowsNoLongerAvailable() async {
        api.listing = .failure(apiError(404, "not_found"))
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        #expect(model.loadError?.isNotFound == true)
        #expect(model.listing == nil)
    }

    @Test func aFailedFirstLoadOffersRetryAndAFailedReloadKeepsTheListing() async {
        api.listings = [.failure(.network), .success(.fixture())]
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        #expect(model.loadError == .network)
        await model.retry()
        #expect(model.listing != nil && model.loadError == nil)
        api.listing = .failure(.network)
        await model.reload()
        #expect(model.listing != nil)
        #expect(model.refreshError == .network)
    }

    @Test func anOfferOpensItsConversation() async {
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        api.offer = .success("cnv9")
        #expect(await model.makeOffer(amount: 2000) == .sent(conversationId: "cnv9"))
        #expect(api.offers == [2000])
    }

    @Test func aPendingOfferOpensTheExistingConversation() async {
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        let body = #"{"error":{"code":"offer_pending","message":"x","conversationId":"cnv2"}}"#
        api.offer = .failure(.from(status: 409, body: Data(body.utf8)))
        #expect(await model.makeOffer(amount: 2000) == .pending(conversationId: "cnv2"))
        api.offer = .failure(apiError(409, "offer_pending"))
        #expect(await model.makeOffer(amount: 2000) == .failed(apiError(409, "offer_pending")))
    }

    @Test func anOutOfRangeOfferReloadsAndShowsTheNewBounds() async {
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        api.offer = .failure(apiError(400, "offer_out_of_range"))
        api.listing = .success(.fixture(price: 3000, offerRange: AmountRange(min: 900, max: 3000)))
        #expect(await model.makeOffer(amount: 800) == .outOfRange(AmountRange(min: 900, max: 3000)))
        #expect(model.listing?.price == 3000)
    }

    @Test func aListingNoLongerForSaleFailsAndReloads() async {
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        let unavailable = apiError(409, "listing_unavailable")
        api.offer = .failure(unavailable)
        api.listing = .success(.fixture(status: .reserved))
        #expect(await model.makeOffer(amount: 2000) == .failed(unavailable))
        #expect(model.listing?.status == .reserved)
    }

    @Test func messagingOpensTheConversationAndABlockReloads() async {
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        #expect(await model.messageSeller() == .openConversation("cnv1"))
        api.conversation = .failure(apiError(403, "blocked"))
        let before = api.listingCalls.count
        #expect(await model.messageSeller() == .failed(apiError(403, "blocked")))
        #expect(api.listingCalls.count == before + 1)
    }

    @Test func deletingIsDoneEvenWhenItWasAlreadyGone() async {
        api.listing = .success(.fixture(isOwner: true))
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        #expect(await model.delete() == .deleted)
        api.deletion = .failure(apiError(404, "not_found"))
        #expect(await model.delete() == .deleted)
        let locked = apiError(409, "listing_locked")
        api.deletion = .failure(locked)
        #expect(await model.delete() == .failed(locked))
    }

    @Test func hidingShowsTheListingTheServerReturns() async {
        api.listing = .success(.fixture(isOwner: true))
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        #expect(await model.setHidden(true) == .done)
        #expect(model.listing?.status == .hidden)
        #expect(model.actions(isSignedIn: true)?.owner?.visibility == .resume)
    }

    @Test func theBundleToggleSendsTheWholeSelection() async {
        api.listing = .success(.fixture(openBundleId: "b1"))
        bundles.review = .success(fixtureBundle(items: [fixtureLine("x")]))
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles, memberId: "me")
        await model.loadIfNeeded()
        #expect(model.bundle?.listingIds == ["x"])
        #expect(await model.toggleBundle() == .done)
        #expect(bundles.saved == [["x", "l1"]])
        #expect(model.listing?.inMyBundle == true)
        #expect(await model.toggleBundle() == .done)
        #expect(bundles.saved.last == ["x"])
        #expect(model.listing?.inMyBundle == false)
    }

    @Test func afterSigningInTheActionRunsOnlyIfTheReloadedListingStillOffersIt() async {
        let model = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        await model.loadIfNeeded()
        api.listing = .success(.fixture(isOwner: true))
        #expect(await model.resolvePending(.makeOffer, memberId: "amina") == nil)
        #expect(model.listing?.isOwner == true)

        let other = ListingDetailViewModel(listingId: "l1", api: api, bundles: bundles)
        api.listing = .success(.fixture())
        await other.loadIfNeeded()
        api.listing = .success(.fixture(acceptedOffer: AcceptedOfferRef(id: "o1", amount: 2000)))
        #expect(await other.resolvePending(.buy, memberId: "karim") == .buy)
        #expect(other.actions(isSignedIn: true)?.buy == .payNow(offerId: "o1", amount: 2000))
    }
}

struct ListingDetailLayoutTests {
    @Test func theGalleryShrinksOnlyOnShortScreens() {
        #expect(ListingDetailLayout.galleryHeight(viewport: 0) == 340)
        #expect(ListingDetailLayout.galleryHeight(viewport: 620) == 340)
        #expect(ListingDetailLayout.galleryHeight(viewport: 450) == 270)
        #expect(ListingDetailLayout.galleryHeight(viewport: 300) == 220)
    }
}
