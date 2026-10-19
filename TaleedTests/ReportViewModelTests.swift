import Foundation
@testable import Taleed
import Testing

// MARK: - Report sheet

@MainActor
struct ReportViewModelTests {
    private let api = FakeListingDetailApi()

    private static let uploaded = UploadedPhoto(key: "reports/k1", url: nil, thumbURL: nil)

    private func model(upload: Result<UploadedPhoto, Taleed.ApiError> = .success(uploaded)) -> ReportViewModel {
        ReportViewModel(target: .listing(id: "l1"), api: api, upload: { _ throws(Taleed.ApiError) in try upload.get() })
    }

    @Test func aReasonIsRequired() async {
        let model = model()
        #expect(!model.canSubmit)
        #expect(await model.submit() == nil)
        model.reason = "COUNTERFEIT"
        #expect(model.canSubmit)
    }

    @Test func sendsTheTrimmedDetailsAndTheUploadedScreenshots() async {
        let model = model()
        model.reason = "COUNTERFEIT"
        model.details = "  Faux sac  "
        await model.addEvidence(Data())
        #expect(await model.submit() == .sent)
        #expect(api.reports.count == 1)
        #expect(api.reports.first?.target == .listing(id: "l1"))
        #expect(api.reports.first?.details == "Faux sac")
        #expect(api.reports.first?.evidenceKeys == ["reports/k1"])
    }

    @Test func alreadyReportedIsTheSameThankYouAndAGoneTargetCloses() async {
        let model = model()
        model.reason = "SCAM"
        api.report = .failure(apiError(409, "already_reported"))
        #expect(await model.submit() == .sent)
        api.report = .failure(apiError(404, "not_found"))
        #expect(await model.submit() == .gone)
        api.report = .failure(.network)
        #expect(await model.submit() == .failed(.network))
        #expect(model.error == .network)
    }

    @Test func detailsStopAt2000CharactersAndScreenshotsAt3() async {
        let model = model()
        model.details = String(repeating: "a", count: 2100)
        #expect(model.details.count == 2000)
        for _ in 0..<4 { await model.addEvidence(Data()) }
        #expect(model.evidence.count == 3)
        #expect(!model.canAddEvidence)
    }

    @Test func aFailedUploadIsLeftOut() async {
        let model = model(upload: .failure(apiError(413, "file_too_large")))
        model.reason = "SPAM"
        await model.addEvidence(Data())
        #expect(model.evidence.first?.error != nil)
        #expect(model.canSubmit)
        #expect(await model.submit() == .sent)
        #expect(api.reports.first?.evidenceKeys == [])
    }
}
