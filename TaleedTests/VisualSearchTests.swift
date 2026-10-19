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

// MARK: - Search by photo

@MainActor
struct VisualSearchTests {
    @Test func aFoundSearchOpensItsResults() async {
        let fake = FakeExploreApi()
        let model = VisualSearchModel(api: fake)
        let outcome = await model.search(photoData())
        #expect(outcome == .found(id: "vs1"))
        #expect(model.phase == .pick)
        // The prepared JPEG went out, then was deleted.
        #expect(fake.uploadedFileExisted == [true])
        #expect(fake.uploadedFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
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
