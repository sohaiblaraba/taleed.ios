import Foundation
@testable import Taleed
import Testing

/// The lists the sell form asked to fetch again.
@MainActor
final class RefreshedLists {
    var calls: [Set<SellReferenceList>] = []
}

/// What the sell form does when sending again cannot work: a photo the API refuses offers no retry, and
/// a choice the API no longer knows fetches its list again before the member picks again.
@MainActor
struct SellRefusalTests {
    private let api = FakeSellApi()
    private let uploads = FakeUploads()
    private let refreshed = RefreshedLists()

    private func filledModel(photos: Int = 2) async -> SellViewModel {
        let model = SellViewModel(api: api, upload: { [uploads] data async throws(Taleed.ApiError) in try await uploads.upload(data) },
                                  refreshLists: { [refreshed] lists in refreshed.calls.append(lists) })
        model.form = validForm()
        await model.addPhotos(Array(repeating: Data(), count: photos))
        return model
    }

    @Test(arguments: [Taleed.ApiError.failed(ApiFailure(status: 413, code: .fileTooLarge)),
                      .failed(ApiFailure(status: 415, code: .unsupportedMediaType))])
    func aPhotoTheApiRefusesOffersNoRetry(error: Taleed.ApiError) async {
        uploads.results = [.failure(error)]
        let model = await filledModel(photos: 1)
        #expect(model.photos.first?.error == error)
        #expect(model.photos.first?.canRetry == false)
        // Sending it again would fail the same way: nothing is sent.
        await model.retry(model.photos[0].id)
        #expect(uploads.calls == 1)
        #expect(await model.publish() == nil)
        #expect(model.fieldErrors[.photos] == .photoUploadFailed)
        model.remove(model.photos[0].id)
        #expect(model.photos.isEmpty)
    }

    @Test(arguments: [(Taleed.ApiError.network, true), (.server(status: 502), true),
                      (.failed(ApiFailure(status: 429, code: .rateLimited)), true),
                      (.failed(ApiFailure(status: 413, code: .fileTooLarge)), false),
                      (.failed(ApiFailure(status: 415, code: .unsupportedMediaType)), false),
                      (.failed(ApiFailure(status: 400, code: .invalidRequest)), false)])
    func retryIsOfferedOnlyWhenTheSamePhotoMayWork(error: Taleed.ApiError, canRetry: Bool) async {
        uploads.results = [.failure(error)]
        let model = await filledModel(photos: 1)
        #expect(model.photos.first?.canRetry == canRetry)
    }

    @Test func aRefusedChoiceRefreshesItsListBeforePickingAgain() async {
        let model = await filledModel()
        api.result = .failure(invalidRequest(["body.brand.id", "body.wilayaId"]))
        #expect(await model.publish() == nil)
        #expect(refreshed.calls == [[.brands, .catalog]])
        #expect(model.fieldErrors[.brand] == .pickAgain)
        #expect(model.fieldErrors[.wilaya] == .pickAgain)
        #expect(!model.isPublishing)
        // Other refusals fetch nothing again.
        api.result = .failure(invalidRequest(["body.title"]))
        _ = await model.publish()
        api.result = .failure(.network)
        _ = await model.publish()
        #expect(refreshed.calls.count == 1)
    }
}
