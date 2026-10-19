import Foundation
@testable import Taleed
import Testing

// MARK: - Fixtures

private let zara = CatalogBrand(id: "b-zara", slug: "zara", name: "Zara")
private let brands = [CatalogBrand(id: "b-hm", slug: "h-m", name: "H&M"), zara]

/// The seller's listing as `GET /listings/{id}` returns it.
func editableListing(
    id: String = "l1", status: Taleed.ListingStatus = .active, isOwner: Bool = true, size: String? = "S",
    brand: ListingBrandRef? = ListingBrandRef(slug: "zara", name: "Zara"),
    category: ListingCategoryRef = ListingCategoryRef(slug: "robes", name: "Robes", parentName: "Femmes", id: "women-dresses",
                                                      parentId: "women"),
    photoIds: [String] = ["p1", "p2"], wilaya: CatalogWilaya? = CatalogWilaya(id: 16, name: "Alger"), price: Int = 2500,
    condition: String? = "VERY_GOOD"
) -> Taleed.ListingDetail {
    Taleed.ListingDetail(
        id: id, title: "Robe fleurie Zara", description: "Robe légère, portée deux fois.", price: price, protectionFee: 175,
        size: size, brand: brand, condition: condition, status: status,
        photos: photoIds.map { ListingPhoto(id: $0, url: URL(string: "https://media.test/\($0).webp"), thumbURL: nil) },
        category: category, shipsFrom: wilaya, viewsCount: 5, favoritesCount: 4, isFavorited: false, isBoosted: false,
        isOwner: isOwner,
        seller: ListingSellerInfo(id: "s1", username: "linakh", displayName: "Lina", avatarURL: nil, isVerified: false,
                                  isOfficial: false, rating: nil, lastSeenAt: nil, isOnline: true),
        acceptedOffer: nil, canBuy: false, orderId: nil, offerRange: nil, canMessage: false, canBundle: false,
        openBundleId: nil, inMyBundle: false, memberItems: [], similar: [], shareURL: nil,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

/// An `EditListingApi` answering from canned results, recording what was sent.
@MainActor
final class FakeEditListingApi: EditListingApi {
    var loads: [Result<Taleed.ListingDetail, Taleed.ApiError>] = []
    var listing: Result<Taleed.ListingDetail, Taleed.ApiError> = .success(TaleedTests.editableListing())
    var updates: [Result<Taleed.ListingDetail, Taleed.ApiError>] = []
    private(set) var sent: [ListingChanges] = []
    private(set) var loadCalls = 0

    func editableListing(id: String) async throws(Taleed.ApiError) -> Taleed.ListingDetail {
        loadCalls += 1
        if !loads.isEmpty { return try loads.removeFirst().get() }
        return try listing.get()
    }

    func updateListing(id: String, changes: ListingChanges) async throws(Taleed.ApiError) -> Taleed.ListingDetail {
        sent.append(changes)
        if !updates.isEmpty { return try updates.removeFirst().get() }
        return TaleedTests.editableListing(price: changes.price ?? 2500)
    }
}

// MARK: - Prefill and changes

struct ListingEditFormTests {
    @Test func theFormIsFilledFromTheListing() {
        let form = SellForm.saved(editableListing(), brands: brands)
        #expect(form.title == "Robe fleurie Zara")
        #expect(form.priceText == "2500")
        #expect(form.parentCategoryId == "women")
        #expect(form.categoryId == "women-dresses")
        #expect(form.topLevelCategoryId == nil)
        #expect(form.brand == .catalog(zara))
        #expect(form.size == "S")
        #expect(form.condition == "VERY_GOOD")
        #expect(form.wilayaId == 16)
        #expect(form.errors(photoCount: 2).isEmpty)
    }

    @Test func aTypedBrandOrOneNotInTheListShowsAsItsName() {
        let typed = SellForm.saved(editableListing(brand: ListingBrandRef(slug: nil, name: "Maison K")), brands: brands)
        #expect(typed.brand == .typed("Maison K"))
        let unknown = SellForm.saved(editableListing(brand: ListingBrandRef(slug: "gone", name: "Gone")), brands: brands)
        #expect(unknown.brand == .typed("Gone"))
        #expect(SellForm.saved(editableListing(brand: nil), brands: brands).brand == .none)
    }

    @Test func anUnknownConditionMustBePickedAgain() {
        let form = SellForm.saved(editableListing(condition: nil), brands: brands)
        #expect(form.condition == nil)
        #expect(form.errors(photoCount: 1)[.condition] == .conditionRequired)
    }

    @Test func nothingChangedSendsNoField() {
        let saved = SellForm.saved(editableListing(), brands: brands)
        #expect(saved.changes(since: saved, photoCount: 2)?.isEmpty == true)
        // Spaces around a value are not a change.
        var spaced = saved
        spaced.title = "  Robe fleurie Zara "
        #expect(spaced.changes(since: saved, photoCount: 2)?.isEmpty == true)
    }

    @Test func onlyTheChangedFieldsAreSent() {
        let saved = SellForm.saved(editableListing(), brands: brands)
        var form = saved
        form.priceText = "2300"
        form.size = "  "
        form.description = "  Robe légère, jamais portée.  "
        let changes = form.changes(since: saved, photoCount: 2)
        #expect(changes == ListingChanges(description: "Robe légère, jamais portée.", price: 2300, size: ""))
    }

    @Test func theBrandIsReplacedOrRemoved() {
        let saved = SellForm.saved(editableListing(), brands: brands)
        var form = saved
        form.brand = .none
        #expect(form.changes(since: saved, photoCount: 1)?.brand == ListingChanges.Brand.none)
        form.brand = .typed("Maison K")
        #expect(form.changes(since: saved, photoCount: 1)?.brand == .typed(name: "Maison K"))
        form.brand = .catalog(CatalogBrand(id: "b-hm", slug: "h-m", name: "H&M"))
        #expect(form.changes(since: saved, photoCount: 1)?.brand == .catalog(id: "b-hm"))
    }

    @Test func aNewCategoryMustBeASubcategory() {
        let saved = SellForm.saved(editableListing(), brands: brands)
        var form = saved
        form.selectParentCategory("men")
        #expect(form.changes(since: saved, photoCount: 1) == nil)
        #expect(form.errors(photoCount: 1)[.subcategory] == .categoryRequired)
        form.categoryId = "men-shoes"
        #expect(form.changes(since: saved, photoCount: 1)?.categoryId == "men-shoes")
    }

    @Test func anOlderListingKeepsItsTopLevelCategoryUntilAnotherIsPicked() {
        let legacy = editableListing(category: ListingCategoryRef(slug: "femmes", name: "Femmes", parentName: nil, id: "women"))
        let saved = SellForm.saved(legacy, brands: brands)
        #expect(saved.parentCategoryId == "women")
        #expect(saved.categoryId == nil)
        #expect(saved.keepsTopLevelCategory)
        var form = saved
        form.priceText = "2000"
        #expect(form.errors(photoCount: 1).isEmpty)
        #expect(form.changes(since: saved, photoCount: 1) == ListingChanges(price: 2000))
        // Another category: a subcategory is needed now, even back on the first one.
        form.selectParentCategory("men")
        #expect(form.errors(photoCount: 1)[.subcategory] == .categoryRequired)
        form.categoryId = "men-shoes"
        #expect(form.changes(since: saved, photoCount: 1)?.categoryId == "men-shoes")
    }

    @MainActor @Test func aListingWithoutWilayaSavesTheMembersOne() {
        let listing = editableListing(wilaya: nil)
        let model = SellViewModel(editing: listing, brands: brands, memberWilayaId: 31, api: FakeEditListingApi(),
                                  upload: { _ async throws(Taleed.ApiError) in UploadedPhoto(key: "k", url: nil, thumbURL: nil) })
        #expect(model.form.wilayaId == 31)
        #expect(model.form.changes(since: model.baseline!.form, photoCount: 2)?.wilayaId == 31)
    }

    @Test func thePhotosAreSentOnlyWhenTheyChange() {
        let baseline = ListingEditBaseline(listingId: "l1", form: SellForm(), photoIds: ["p1", "p2"])
        #expect(baseline.photoChanges([.kept(id: "p1"), .kept(id: "p2")]) == nil)
        #expect(baseline.photoChanges([.kept(id: "p2"), .kept(id: "p1")]) == [.kept(id: "p2"), .kept(id: "p1")])
        #expect(baseline.photoChanges([.kept(id: "p1")]) == [.kept(id: "p1")])
        #expect(baseline.photoChanges([.added(key: "k1"), .kept(id: "p1"), .kept(id: "p2")])
            == [.added(key: "k1"), .kept(id: "p1"), .kept(id: "p2")])
    }

    @Test func aMissingPhotoIdMeansTheListingChangedElsewhere() {
        let mapping = SellForm.mapping(of: invalidRequest(["body.photos.1.id", "body.photos.0.key"]).issues)
        #expect(mapping.listingChanged)
        #expect(mapping.rejectedPhotos == [0])
    }

    @Test func aReloadKeepsWhatTheMemberChanged() {
        let old = SellForm.saved(editableListing(), brands: brands)
        var edited = old
        edited.priceText = "2300"
        var fresh = old
        fresh.title = "Robe fleurie (édité ailleurs)"
        fresh.priceText = "2400"
        let reloaded = SellForm.reloaded(edited: edited, old: old, fresh: fresh)
        #expect(reloaded.title == "Robe fleurie (édité ailleurs)")
        #expect(reloaded.priceText == "2300")
    }

    @Test(arguments: [(Taleed.ListingStatus.active, ListingEditability.editable), (.hidden, .editable), (.reserved, .locked),
                      (.sold, .locked), (.unknown, .locked)])
    func onlyActiveAndHiddenListingsOpenTheForm(status: Taleed.ListingStatus, expected: ListingEditability) {
        #expect(ListingEditability(editableListing(status: status)) == expected)
        #expect(ListingEditability(editableListing(status: status, isOwner: false)) == .notOwner)
    }
}

// MARK: - Saving

@MainActor
struct ListingSaveTests {
    private let api = FakeEditListingApi()
    private let uploads = FakeUploads()

    private func model(_ listing: Taleed.ListingDetail = editableListing()) -> SellViewModel {
        SellViewModel(editing: listing, brands: brands, memberWilayaId: 25, api: api,
                      upload: { [uploads] data async throws(Taleed.ApiError) in try await uploads.upload(data) })
    }

    @Test func theFormOpensWithTheListingsPhotosInOrder() {
        let model = model()
        #expect(model.isEditing)
        #expect(model.photos.map(\.reference) == [.kept(id: "p1"), .kept(id: "p2")])
        #expect(model.canPublish)
    }

    @Test func savingSendsOnlyTheChangesAndReturnsTheListing() async {
        let model = model()
        model.form.priceText = "2300"
        model.form.size = ""
        guard case let .saved(listing) = await model.save() else {
            Issue.record("not saved")
            return
        }
        #expect(listing.price == 2300)
        #expect(api.sent == [ListingChanges(price: 2300, size: "")])
    }

    @Test func makingTheSecondPhotoTheCoverSendsTheNewOrder() async {
        let model = model()
        model.makeCover(model.photos[1].id)
        _ = await model.save()
        #expect(api.sent.first?.photos == [.kept(id: "p2"), .kept(id: "p1")])
    }

    @Test func aNewPhotoIsSentWithItsKeyAndARemovedOneIsLeftOut() async {
        let model = model()
        model.remove(model.photos[0].id)
        await model.addPhotos([Data()])
        _ = await model.save()
        #expect(api.sent.first?.photos == [.kept(id: "p2"), .added(key: "listings/k1")])
    }

    @Test func removingEveryPhotoIsRefusedBeforeSending() async {
        let model = model()
        for photo in model.photos { model.remove(photo.id) }
        #expect(await model.save() == .refused)
        #expect(model.fieldErrors[.photos] == .photoRequired)
        #expect(api.sent.isEmpty)
    }

    @Test func aPriceOutOfRangeIsRefusedBeforeSending() async {
        let model = model()
        model.form.priceText = "50"
        #expect(await model.save() == .refused)
        #expect(model.fieldErrors[.price] == .priceRange(min: 100, max: 10_000_000))
        #expect(api.sent.isEmpty)
    }

    @Test func aLockedListingLeavesTheForm() async {
        let model = model()
        api.updates = [.failure(apiError(409, "listing_locked"))]
        guard case let .cannotEdit(error) = await model.save() else {
            Issue.record("expected cannotEdit")
            return
        }
        #expect(error.code == .listingLocked)
    }

    @Test func aDeletedListingIsGone() async {
        api.updates = [.failure(apiError(404, "not_found"))]
        #expect(await model().save() == .gone)
    }

    @Test func otherFailuresStayOnTheForm() async {
        let model = model()
        api.updates = [.failure(.network)]
        #expect(await model.save() == .refused)
        #expect(model.publishError == .network)
        // Saving again sends the same request.
        _ = await model.save()
        #expect(api.sent.count == 2)
        #expect(api.sent[0] == api.sent[1])
    }

    @Test func fieldIssuesFromTheApiAreShown() async {
        let model = model()
        api.updates = [.failure(invalidRequest(["body.title"]))]
        model.form.title = "Robe"
        #expect(await model.save() == .refused)
        #expect(model.fieldErrors[.title] == .titleLength(min: 3, max: 80))
    }

    @Test func aPhotoEditedElsewhereReloadsTheListingAndKeepsTheMembersChanges() async {
        let model = model()
        model.form.priceText = "2300"
        await model.addPhotos([Data()])
        api.updates = [.failure(invalidRequest(["body.photos.1.id"]))]
        #expect(await model.save() == .listingChanged)
        model.reloadListing(editableListing(photoIds: ["p1", "p3"]), brands: brands)
        #expect(model.photos.map(\.reference) == [.kept(id: "p1"), .kept(id: "p3"), .added(key: "listings/k1")])
        #expect(model.form.priceText == "2300")
        _ = await model.save()
        #expect(api.sent.last?.photos == [.kept(id: "p1"), .kept(id: "p3"), .added(key: "listings/k1")])
        #expect(api.sent.last?.price == 2300)
    }
}

// MARK: - The edit screen

@MainActor
struct EditListingScreenTests {
    private let api = FakeEditListingApi()

    private func screen() -> EditListingViewModel {
        EditListingViewModel(listingId: "l1", api: api,
                             upload: { _ async throws(Taleed.ApiError) in UploadedPhoto(key: "k", url: nil, thumbURL: nil) },
                             brands: { brands }, memberWilayaId: { 16 })
    }

    @Test func theSellersActiveListingOpensTheForm() async {
        let screen = screen()
        await screen.loadIfNeeded()
        #expect(screen.form?.form.brand == .catalog(zara))
    }

    @Test func someoneElsesListingIsNotFound() async {
        api.listing = .success(editableListing(isOwner: false))
        let screen = screen()
        await screen.loadIfNeeded()
        guard case .notFound = screen.phase else { Issue.record("expected notFound"); return }
    }

    @Test func aReservedListingCannotBeEdited() async {
        api.listing = .success(editableListing(status: .reserved))
        let screen = screen()
        await screen.loadIfNeeded()
        guard case .locked = screen.phase else { Issue.record("expected locked"); return }
    }

    @Test func aFailedLoadOffersRetry() async {
        api.loads = [.failure(.network)]
        let screen = screen()
        await screen.loadIfNeeded()
        guard case .failed(.network) = screen.phase else { Issue.record("expected failed"); return }
        await screen.retry()
        #expect(screen.form != nil)
        api.loads = [.failure(apiError(404, "not_found"))]
        let gone = self.screen()
        await gone.loadIfNeeded()
        guard case .notFound = gone.phase else { Issue.record("expected notFound"); return }
    }

    @Test func aPhotoEditedElsewhereReloadsIntoTheForm() async {
        let screen = screen()
        await screen.loadIfNeeded()
        api.updates = [.failure(invalidRequest(["body.photos.0.id"]))]
        api.listing = .success(editableListing(photoIds: ["p9"]))
        #expect(await screen.save() == .listingChanged)
        #expect(screen.showsReloadNotice)
        #expect(screen.form?.photos.map(\.reference) == [.kept(id: "p9")])
    }

    @Test func aListingReservedMeanwhileLeavesTheForm() async {
        let screen = screen()
        await screen.loadIfNeeded()
        api.updates = [.failure(invalidRequest(["body.photos.0.id"]))]
        api.listing = .success(editableListing(status: .reserved))
        guard case .cannotEdit = await screen.save() else { Issue.record("expected cannotEdit"); return }
    }
}
