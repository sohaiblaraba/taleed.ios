import Foundation
@testable import Taleed
import Testing

// MARK: - Fakes

/// A `SellApi` answering from a canned result, recording what was sent.
@MainActor
final class FakeSellApi: SellApi {
    var result: Result<String, Taleed.ApiError> = .success("lst1")
    private(set) var sent: [ListingSubmission] = []

    func createListing(_ listing: ListingSubmission) async throws(Taleed.ApiError) -> String {
        sent.append(listing)
        return try result.get()
    }
}

/// Uploads answering in turn from `results` (then success), numbering the keys.
@MainActor
final class FakeUploads {
    var results: [Result<Void, Taleed.ApiError>] = []
    private(set) var calls = 0

    func upload(_ data: Data) async throws(Taleed.ApiError) -> UploadedPhoto {
        calls += 1
        if !results.isEmpty, case let .failure(error) = results.removeFirst() { throw error }
        return UploadedPhoto(key: "listings/k\(calls)", url: nil, thumbURL: nil)
    }
}

private func invalidRequest(_ paths: [String]) -> Taleed.ApiError {
    let issues = paths.map { #"{"path":"\#($0)","message":"x"}"# }.joined(separator: ",")
    return .from(status: 400, body: Data(#"{"error":{"code":"invalid_request","message":"x","issues":[\#(issues)]}}"#.utf8))
}

private let zara = CatalogBrand(id: "b-zara", slug: "zara", name: "Zara")
private let brands = [CatalogBrand(id: "b-hm", slug: "h-m", name: "H&M"), zara,
                      CatalogBrand(id: "b-zr", slug: "zara-home", name: "Zara Home")]

/// A form that passes every check.
private func validForm() -> SellForm {
    var form = SellForm()
    form.title = "  Veste test  "
    form.description = "  Portée deux fois, aucun défaut.  "
    form.priceText = "3000"
    form.selectParentCategory("women")
    form.categoryId = "women-clothes"
    form.condition = "VERY_GOOD"
    form.wilayaId = 16
    return form
}

// MARK: - Form checks

struct SellFormTests {
    @Test func anEmptyFormNamesEveryRequiredField() {
        let errors = SellForm().errors(photoCount: 0)
        #expect(errors[.photos] == .photoRequired)
        #expect(errors[.title] == .titleLength(min: 3, max: 80))
        #expect(errors[.description] == .descriptionLength(min: 10, max: 2000))
        #expect(errors[.category] == .categoryRequired)
        #expect(errors[.subcategory] == nil)
        #expect(errors[.condition] == .conditionRequired)
        #expect(errors[.price] == .priceRange(min: 100, max: 10_000_000))
        #expect(errors[.brand] == nil && errors[.size] == nil && errors[.wilaya] == nil)
    }

    @Test func aValidFormHasNoError() {
        #expect(validForm().errors(photoCount: 1).isEmpty)
    }

    @Test func lengthsCountAfterTrimming() {
        var form = validForm()
        form.title = "  ab  "
        #expect(form.titleError != nil)
        form.title = "abc"
        #expect(form.titleError == nil)
        form.description = "   123456789   "
        #expect(form.descriptionError != nil)
        form.description = "1234567890"
        #expect(form.descriptionError == nil)
    }

    @Test func fieldsStopAtTheirLimits() {
        #expect(SellForm.cappedTitle(String(repeating: "a", count: 90)).count == 80)
        #expect(SellForm.cappedDescription(String(repeating: "a", count: 2100)).count == 2000)
        #expect(SellForm.cappedSize(String(repeating: "a", count: 40)).count == 30)
        #expect(SellForm.cappedBrandSearch(String(repeating: "a", count: 70)).count == 60)
        // Counted in UTF-16 units, as the API: an emoji takes two.
        #expect(SellForm.cappedTitle(String(repeating: "👕", count: 50)).count == 40)
    }

    @Test(arguments: [("", false), ("50", false), ("99", false), ("100", true), ("10000000", true), ("10000001", false)])
    func priceIsBetween100And10Million(text: String, passes: Bool) {
        var form = validForm()
        form.priceText = text
        #expect((form.priceError == nil) == passes)
    }

    @Test func aTopLevelCategoryAloneAsksForTheSubcategory() {
        var form = validForm()
        form.selectParentCategory("men")
        #expect(form.categoryId == nil)
        let errors = form.errors(photoCount: 1)
        #expect(errors[.subcategory] == .categoryRequired)
        #expect(errors[.category] == nil)
        // Picking the same category again keeps the subcategory.
        form.categoryId = "men-shoes"
        form.selectParentCategory("men")
        #expect(form.categoryId == "men-shoes")
    }

    @Test func theSubmissionIsTrimmedAndKeepsThePhotoOrder() {
        var form = validForm()
        form.size = "  "
        form.brand = .typed("Maison Kitsuné")
        let submission = form.submission(photoKeys: ["k2", "k1"])
        #expect(submission == ListingSubmission(title: "Veste test", description: "Portée deux fois, aucun défaut.", price: 3000,
                                                categoryId: "women-clothes", condition: "VERY_GOOD",
                                                brand: .typed(name: "Maison Kitsuné"), size: nil, wilayaId: 16,
                                                photoKeys: ["k2", "k1"]))
        form.brand = .catalog(zara)
        form.size = " M "
        #expect(form.submission(photoKeys: ["k1"])?.brand == .catalog(id: "b-zara"))
        #expect(form.submission(photoKeys: ["k1"])?.size == "M")
        form.brand = .none
        #expect(form.submission(photoKeys: ["k1"])?.brand == nil)
        #expect(form.submission(photoKeys: []) == nil)
    }

    @Test func onlyConditionsThisBuildCanSendAreOffered() {
        #expect(SellLimits.isSendableCondition("VERY_GOOD"))
        #expect(!SellLimits.isSendableCondition("LIKE_NEW"))
        #expect(!SellLimits.isSendableCondition("unknown_default_open_api"))
    }
}

// MARK: - Brand combobox

struct SellBrandTests {
    @Test func aTypedNameMatchingACatalogBrandIgnoringCaseIsThatBrand() {
        #expect(SellBrand.choice(forTyped: " zara ", brands: brands) == .catalog(zara))
        #expect(SellBrand.choice(forTyped: "Maison Kitsuné", brands: brands) == .typed("Maison Kitsuné"))
        #expect(SellBrand.choice(forTyped: "   ", brands: brands) == nil)
    }

    @Test func useTheTypedNameOnlyWhenNoBrandHasIt() {
        #expect(SellBrand.offersTypedName("Zar", brands: brands))
        #expect(!SellBrand.offersTypedName("ZARA", brands: brands))
        #expect(!SellBrand.offersTypedName("", brands: brands))
    }

    @Test func theSearchMatchesPartOfTheName() {
        #expect(SellBrand.matches("zar", in: brands).map(\.id) == ["b-zara", "b-zr"])
        #expect(SellBrand.matches("", in: brands).count == 3)
        #expect(SellBrand.matches("home", in: brands).map(\.id) == ["b-zr"])
    }

    @Test func aTypedNameStopsAt60Characters() {
        let long = String(repeating: "b", count: 70)
        #expect(SellBrand.choice(forTyped: long, brands: brands)?.displayName?.count == 60)
    }
}

// MARK: - API issues

struct SellIssueMappingTests {
    @Test func eachPathLandsOnItsField() {
        let issues = invalidRequest(["body.title", "body.categoryId", "body.brand.id", "body.wilayaId", "body.size",
                                     "body.price", "body.condition", "body.description"]).issues
        let mapping = SellForm.mapping(of: issues)
        #expect(mapping.errors[.title] == .titleLength(min: 3, max: 80))
        #expect(mapping.errors[.subcategory] == .pickAgain)
        #expect(mapping.errors[.brand] == .pickAgain)
        #expect(mapping.errors[.wilaya] == .pickAgain)
        #expect(mapping.errors[.size] == .tooLong(max: 30))
        #expect(mapping.errors[.price] == .priceRange(min: 100, max: 10_000_000))
        #expect(mapping.errors[.condition] == .conditionRequired)
        #expect(mapping.errors[.description] == .descriptionLength(min: 10, max: 2000))
        #expect(!mapping.hasUnplacedIssues)
    }

    @Test func refusedPhotoKeysAreListedByPosition() {
        let mapping = SellForm.mapping(of: invalidRequest(["body.photos.2.key", "body.photos.0.key", "body.photos.2.key"]).issues)
        #expect(mapping.rejectedPhotos == [0, 2])
        #expect(mapping.errors.isEmpty)
        #expect(SellForm.mapping(of: invalidRequest(["body.photos"]).issues).errors[.photos] == .photoRequired)
    }

    @Test func otherPathsOnlySayCheckTheFields() {
        let mapping = SellForm.mapping(of: invalidRequest(["body.unknownField", "query.cursor"]).issues)
        #expect(mapping.errors.isEmpty)
        #expect(mapping.hasUnplacedIssues)
    }
}

// MARK: - Texts

struct SellMessagesTests {
    private static let errors: [SellFieldError] = [
        .photoRequired, .photoUploadFailed, .titleLength(min: 3, max: 80), .descriptionLength(min: 10, max: 2000),
        .categoryRequired, .priceRange(min: 100, max: 10_000_000), .conditionRequired, .pickAgain, .tooLong(max: 30),
    ]

    @Test(arguments: AppLanguage.allCases)
    func everyErrorHasATextInEveryLanguage(language: AppLanguage) {
        for error in Self.errors {
            let text = SellMessages.text(for: error, language: language)
            #expect(!text.isEmpty)
            #expect(!text.contains("_"), "missing translation: \(text)")
            #expect(!text.contains("%"), "unfilled argument: \(text)")
        }
    }

    @Test func thePriceRangeUsesTheAppsPriceFormat() {
        let text = SellMessages.text(for: .priceRange(min: 100, max: 10_000_000), language: .fr)
        #expect(text.contains(PriceFormatter.format(100, language: .fr)))
        #expect(text.contains(PriceFormatter.format(10_000_000, language: .fr)))
    }

    @Test func sizeSuggestionsMatchTheTypedText() {
        let sizes = ["M", "XL", "6 mois", "12 mois", "38", "38 EU"]
        #expect(SellSizeSuggestions.matching("m", in: sizes) == ["6 mois", "12 mois"])
        #expect(SellSizeSuggestions.matching("38", in: sizes) == ["38 EU"])
        #expect(SellSizeSuggestions.matching("", in: sizes) == sizes)
        #expect(SellSizeSuggestions.matching("", in: (1...20).map(String.init)).count == SellSizeSuggestions.limit)
    }
}

// MARK: - View model

@MainActor
struct SellViewModelTests {
    private let api = FakeSellApi()
    private let uploads = FakeUploads()

    private func model() -> SellViewModel {
        SellViewModel(api: api, upload: { [uploads] data async throws(Taleed.ApiError) in try await uploads.upload(data) },
                      wilayaId: 25)
    }

    private func filledModel(photos: Int = 2) async -> SellViewModel {
        let model = model()
        var form = validForm()
        form.wilayaId = model.form.wilayaId
        model.form = form
        await model.addPhotos(Array(repeating: Data(), count: photos))
        return model
    }

    @Test func theMembersWilayaIsPrefilledOnce() {
        let model = model()
        #expect(model.form.wilayaId == 25)
        model.memberWilayaDidLoad(16)
        #expect(model.form.wilayaId == 25)
        model.form.wilayaId = nil
        model.memberWilayaDidLoad(16)
        #expect(model.form.wilayaId == 16)
    }

    @Test func photosUploadAtOnceUpToFive() async {
        let model = model()
        await model.addPhotos(Array(repeating: Data(), count: 7))
        #expect(model.photos.count == 5)
        #expect(uploads.calls == 5)
        #expect(model.photos.allSatisfy { $0.key != nil })
        #expect(!model.canAddPhotos)
        await model.addPhotos([Data()])
        #expect(model.photos.count == 5)
    }

    @Test func publishesTheKeysInDisplayOrder() async {
        let model = await filledModel(photos: 3)
        model.makeCover(model.photos[2].id)
        #expect(await model.publish() == "lst1")
        #expect(api.sent.count == 1)
        #expect(api.sent.first?.photoKeys == ["listings/k3", "listings/k1", "listings/k2"])
        #expect(api.sent.first?.title == "Veste test")
        #expect(api.sent.first?.wilayaId == 25)
    }

    @Test func aRefusedFormSendsNothingAndPointsAtTheFirstError() async {
        let model = await filledModel()
        model.form.priceText = "50"
        model.form.selectParentCategory("men")
        #expect(await model.publish() == nil)
        #expect(api.sent.isEmpty)
        #expect(model.refusals == 1)
        #expect(model.fieldErrors[.price] == .priceRange(min: 100, max: 10_000_000))
        #expect(model.fieldErrors[.subcategory] == .categoryRequired)
        #expect(model.firstErrorField == .subcategory)
    }

    @Test func noPhotoIsAnError() async {
        let model = model()
        model.form = validForm()
        #expect(await model.publish() == nil)
        #expect(model.fieldErrors == [.photos: .photoRequired])
        await model.addPhotos([Data()])
        #expect(model.fieldErrors[.photos] == nil)
    }

    @Test func errorsGoAsTheMemberFixesEachField() async {
        let model = model()
        _ = await model.publish()
        #expect(model.fieldErrors[.title] != nil)
        model.form.title = "Ve"
        #expect(model.fieldErrors[.title] != nil)
        model.form.title = "Veste"
        #expect(model.fieldErrors[.title] == nil)
        // Untouched fields keep theirs; no new error appears before the next publish.
        #expect(model.fieldErrors[.price] != nil)
        model.form.size = String(repeating: "a", count: 3)
        #expect(model.fieldErrors[.size] == nil)
        // The category was missing: once picked, the subcategory still is.
        model.form.selectParentCategory("women")
        #expect(model.fieldErrors[.category] == nil)
        #expect(model.fieldErrors[.subcategory] == .categoryRequired)
        model.form.categoryId = "women-clothes"
        #expect(model.fieldErrors[.subcategory] == nil)
    }

    @Test func aFailedUploadShowsRetryAndBlocksPublishing() async {
        uploads.results = [.failure(.network)]
        let model = await filledModel(photos: 1)
        #expect(model.photos.first?.error == .network)
        #expect(await model.publish() == nil)
        #expect(model.fieldErrors[.photos] == .photoUploadFailed)
        #expect(api.sent.isEmpty)
        await model.retry(model.photos[0].id)
        #expect(model.photos.first?.key == "listings/k2")
        #expect(model.fieldErrors[.photos] == nil)
        #expect(await model.publish() == "lst1")
    }

    @Test func removingAFailedPhotoClearsItsError() async {
        uploads.results = [.success(()), .failure(.network)]
        let model = await filledModel(photos: 2)
        _ = await model.publish()
        #expect(model.fieldErrors[.photos] == .photoUploadFailed)
        let failed = model.photos.first { $0.error != nil }
        #expect(failed != nil)
        model.remove(failed?.id ?? UUID())
        #expect(model.fieldErrors[.photos] == nil)
        #expect(model.photos.count == 1)
    }

    @Test func theApisFieldErrorsAreShownAndRefusedPhotosUploadAgain() async {
        let model = await filledModel(photos: 2)
        api.result = .failure(invalidRequest(["body.photos.1.key", "body.categoryId"]))
        #expect(await model.publish() == nil)
        #expect(model.publishError?.code == .invalidRequest)
        #expect(model.fieldErrors[.subcategory] == .pickAgain)
        // The second photo goes up again (a third upload).
        for _ in 0..<20 where uploads.calls < 3 { await Task.yield() }
        #expect(uploads.calls == 3)
        // Picking another subcategory clears "pick again".
        model.form.categoryId = "women-shoes"
        #expect(model.fieldErrors[.subcategory] == nil)
    }

    @Test func otherFailuresAreShownAndPublishingAgainSendsTheSameRequest() async {
        let model = await filledModel()
        api.result = .failure(.network)
        #expect(await model.publish() == nil)
        #expect(model.publishError == .network)
        #expect(model.fieldErrors.isEmpty)
        api.result = .success("lst1")
        #expect(await model.publish() == "lst1")
        #expect(api.sent.count == 2)
        #expect(api.sent[0] == api.sent[1])
        #expect(model.publishError == nil)
    }

    @Test func resetStartsOverWithTheWilaya() async {
        let model = await filledModel()
        model.reset(wilayaId: 31)
        #expect(model.photos.isEmpty)
        #expect(model.form == { var form = SellForm(); form.wilayaId = 31; return form }())
        #expect(model.fieldErrors.isEmpty)
        #expect(model.resets == 1)
    }
}
