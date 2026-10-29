import Foundation
@testable import Taleed
import Testing
import UIKit

/// A small JPEG, as a picked photo.
private func photoData() -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30))
    return renderer.jpegData(withCompressionQuality: 0.9) { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
    }
}

/// A consent store of its own, empty.
@MainActor
private func consentStore(_ name: String) -> PhotoSearchConsentStore {
    let suite = "VisualSearchTests.\(name)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    return PhotoSearchConsentStore(defaults: defaults)
}

// MARK: - Search by photo

@MainActor
struct VisualSearchTests {
    @Test func aFoundSearchOpensItsResults() async {
        let fake = FakeExploreApi()
        let model = VisualSearchModel(api: fake)
        let outcome = await model.search(photoData())
        #expect(outcome == .found(id: "vs1"))
        #expect(fake.sentConsents == [true])
        #expect(model.phase == .pick)
        // The prepared JPEG went out, then was deleted.
        #expect(fake.uploadedFileExisted == [true])
        #expect(fake.uploadedFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    // MARK: Consent to Jina AI (slice I)

    @Test func everySearchSendsTheConsent() async {
        let fake = FakeExploreApi()
        let model = VisualSearchModel(api: fake, consent: consentStore("sends"))
        model.open(userId: "u1")
        model.agreeToConsent()
        _ = await model.search(photoData())
        _ = await model.search(photoData())
        #expect(fake.sentConsents == [true, true])
    }

    @Test func theFirstSearchAsksAndCancelSendsNothing() async {
        let fake = FakeExploreApi()
        let store = consentStore("cancel")
        let model = VisualSearchModel(api: fake, consent: store)
        model.open(userId: "u1")
        #expect(model.phase == .consent)
        // "Annuler" closes the sheet: nothing is stored or sent.
        model.reset()
        #expect(model.phase == .consent)
        #expect(!store.hasConsent(userId: "u1"))
        #expect(fake.uploadedFiles.isEmpty)
    }

    @Test func agreeingIsRememberedPerAccount() {
        let store = consentStore("accounts")
        let model = VisualSearchModel(api: FakeExploreApi(), consent: store)
        model.open(userId: "u1")
        model.agreeToConsent()
        #expect(model.phase == .pick)
        #expect(store.hasConsent(userId: "u1"))
        // The same account again: no step.
        model.reset()
        model.open(userId: "u1")
        #expect(model.phase == .pick)
        // Another account on the device, and a signed-out visitor: the step again.
        model.open(userId: "u2")
        #expect(model.phase == .consent)
        model.open(userId: nil)
        #expect(model.phase == .consent)
        #expect(PhotoSearchConsentStore.key(for: nil) == "taleed.photoSearchConsent.guest")
        #expect(PhotoSearchConsentStore.key(for: "u1") == "taleed.photoSearchConsent.u1")
    }

    @Test func aConsentTheServerDoesNotHaveIsAskedAgain() async {
        let fake = FakeExploreApi()
        fake.queuedCreateResults = [.failure(.failed(ApiFailure(status: 400, code: .aiConsentRequired)))]
        let store = consentStore("required")
        let model = VisualSearchModel(api: fake, consent: store)
        model.open(userId: "u1")
        model.agreeToConsent()
        #expect(await model.search(photoData()) == .failed)
        // The stored consent is gone and the sheet shows the step again, with no error.
        #expect(model.phase == .consent)
        #expect(model.photo == nil)
        #expect(!store.hasConsent(userId: "u1"))
        model.agreeToConsent()
        #expect(await model.search(photoData()) == .found(id: "vs1"))
    }

    @Test func aPhotoThatCannotBeReadSaysSo() {
        let model = VisualSearchModel(api: FakeExploreApi(), consent: consentStore("unreadable"))
        model.open(userId: "u1")
        model.agreeToConsent()
        // An iCloud photo that cannot download: the network message, and the buttons to pick again.
        model.photoUnreadable(downloadFailed: true)
        #expect(model.phase == .failed(.network, canRetry: false))
        #expect(model.photo == nil)
        // A photo the device cannot hand over: not supported, as the API's 415.
        model.photoUnreadable(downloadFailed: false)
        #expect(model.phase == .failed(.failed(ApiFailure(status: 415, code: .unsupportedMediaType)), canRetry: false))
        model.reset()
        #expect(model.phase == .pick)
    }

    @Test func theFeatureTurnedOffClosesTheSheet() async {
        let fake = FakeExploreApi()
        fake.createResult = .failure(.failed(ApiFailure(status: 503, code: .featureDisabled)))
        let model = VisualSearchModel(api: fake)
        #expect(await model.search(photoData()) == .disabled)
        #expect(model.phase == .pick)
    }

    @Test func aServerFailureOffersARetryWithTheSamePhoto() async {
        let fake = FakeExploreApi()
        fake.createResult = .failure(.server(status: 500))
        let model = VisualSearchModel(api: fake)
        #expect(await model.search(photoData()) == .failed)
        #expect(model.phase == .failed(.server(status: 500), canRetry: true))
        fake.createResult = .success(.fixture(id: "vs2"))
        #expect(await model.retry() == .found(id: "vs2"))
        #expect(fake.uploadedFiles.count == 2)
    }

    @Test func aRefusedPhotoNeedsAnotherPhoto() async {
        let fake = FakeExploreApi()
        fake.createResult = .failure(.failed(ApiFailure(status: 413, code: .fileTooLarge)))
        let model = VisualSearchModel(api: fake)
        #expect(await model.search(photoData()) == .failed)
        #expect(model.phase == .failed(.failed(ApiFailure(status: 413, code: .fileTooLarge)), canRetry: false))
    }

    @Test func dataThatIsNotAnImageNeverReachesTheApi() async {
        let fake = FakeExploreApi()
        let model = VisualSearchModel(api: fake)
        #expect(await model.search(Data("not an image".utf8)) == .failed)
        #expect(model.phase == .failed(.failed(ApiFailure(status: 415, code: .unsupportedMediaType)), canRetry: false))
        #expect(fake.uploadedFiles.isEmpty)
    }

    @Test func resultsKeepThePhotoAndTheWeakMatchFlag() async {
        let fake = FakeExploreApi()
        fake.pages = [nil: .success(.fixture(weakMatch: true, items: [.fixture(id: "a")], nextCursor: "n")),
                      "n": .success(.fixture(weakMatch: true, items: [.fixture(id: "a"), .fixture(id: "b")]))]
        let model = VisualSearchResultsViewModel(id: "vs1", api: fake)
        await model.results.loadIfNeeded()
        await model.results.loadMore()
        #expect(model.weakMatch)
        #expect(model.photoURL?.absoluteString == "https://media.taleed.app/visual/a.webp")
        #expect(model.results.items.map(\.id) == ["a", "b"])
        #expect(!model.hasExpired)
    }

    @Test func anExpiredSearchAsksForANewOne() async {
        let fake = FakeExploreApi()
        fake.pages = [nil: .failure(.failed(ApiFailure(status: 404, code: .notFound)))]
        let model = VisualSearchResultsViewModel(id: "old", api: fake)
        await model.results.loadIfNeeded()
        #expect(model.hasExpired)
    }

    @Test(arguments: [(ApiError.network, true), (.server(status: 500), true), (.rateLimited(retryAfter: 5), true),
                      (.failed(ApiFailure(status: 415, code: .unsupportedMediaType)), false),
                      (.failed(ApiFailure(status: 400, code: .invalidRequest)), false)])
    func retryIsOfferedWhenTheSamePhotoMayWork(error: ApiError, canRetry: Bool) {
        #expect(VisualSearchModel.canRetry(error) == canRetry)
    }
}
