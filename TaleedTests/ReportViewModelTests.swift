import Foundation
@testable import Taleed
import TaleedAPI
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

    /// A reason this build cannot encode is never sent as another category (`OTHER`).
    @Test func aReasonUnknownToThisBuildIsNotSentAsAnotherOne() async {
        let api = GeneratedTaleedApi(session: ApiSession(environment: .fixture(), language: .fr, configuration: .init()))
        do {
            try await api.report(.listing(id: "l1"), reason: "NEW_REASON", details: nil, evidenceKeys: [])
            Issue.record("an unknown reason was sent")
        } catch {
            #expect(error.code == .invalidRequest)
        }
    }

    @Test func anUnreadablePhotoIsAFailedTileThatCountsAndIsLeftOut() async {
        let model = model()
        model.reason = "OTHER"
        model.addUnreadableEvidence()
        #expect(model.evidence.count == 1)
        #expect(model.evidence.first?.error?.code == .unsupportedMediaType)
        #expect(model.evidence.first?.isUploading == false)
        await model.addEvidence(Data())
        await model.addEvidence(Data())
        #expect(!model.canAddEvidence)
        model.addUnreadableEvidence()
        #expect(model.evidence.count == 3)
        #expect(await model.submit() == .sent)
        #expect(api.reports.first?.evidenceKeys == ["reports/k1", "reports/k1"])
        model.removeEvidence(model.evidence[0].id)
        #expect(model.canAddEvidence)
    }

    /// `403 forbidden` (self), `429` and a lost connection stay in the sheet with their message,
    /// and the member can send again.
    @Test func otherFailuresStayInTheSheetAndCanBeSentAgain() async {
        let model = model()
        model.reason = "HARASSMENT"
        for failure in [apiError(403, "forbidden"), apiError(429, "rate_limited"), apiError(403, "banned")] {
            api.report = .failure(failure)
            #expect(await model.submit() == .failed(failure))
            #expect(model.error == failure)
            #expect(model.canSubmit)
        }
        api.report = .success(())
        #expect(await model.submit() == .sent)
        #expect(model.error == nil)
    }

    @Test func whitespaceOnlyDetailsAreLeftOut() async {
        let model = model()
        model.reason = "SPAM"
        model.details = " \n  "
        #expect(await model.submit() == .sent)
        #expect(api.reports.first?.details == nil)
    }

    /// The 2 000 characters are counted in UTF-16 units, as the API counts them.
    @Test func theDetailsLimitCountsUTF16Units() {
        let model = model()
        model.details = String(repeating: "😀", count: 1001)
        #expect(model.details.utf16.count <= 2000)
        #expect(model.details.utf16.count == 2000)
    }

    @Test func nothingIsSentWhileAScreenshotUploads() async {
        let gate = AsyncStream<Void>.makeStream()
        let model = ReportViewModel(target: .member(id: "u1"), api: api, upload: { _ throws(Taleed.ApiError) in
            for await _ in gate.stream { break }
            return Self.uploaded
        })
        model.reason = "SCAM"
        let upload = Task { await model.addEvidence(Data()) }
        while model.evidence.isEmpty { await Task.yield() }
        #expect(model.isUploading)
        #expect(!model.canSubmit)
        gate.continuation.yield()
        await upload.value
        #expect(model.canSubmit)
    }

    /// Exactly one target in the body, and no `evidenceKeys` without a screenshot (slice C).
    @Test func theRequestCarriesExactlyOneTarget() {
        let listing = ReportCreate(.listing(id: "l1"), reason: .counterfeit, details: nil, evidenceKeys: ["k"])
        #expect(listing.listingId == "l1" && listing.memberId == nil && listing.conversationId == nil)
        #expect(listing.evidenceKeys == ["k"])
        let member = ReportCreate(.member(id: "u1"), reason: .scam, details: "x", evidenceKeys: [])
        #expect(member.memberId == "u1" && member.listingId == nil && member.conversationId == nil)
        #expect(member.evidenceKeys == nil)
        let conversation = ReportCreate(.conversation(id: "c1"), reason: .harassment, details: nil, evidenceKeys: [])
        #expect(conversation.conversationId == "c1" && conversation.listingId == nil && conversation.memberId == nil)
    }

    /// The sheet lists the catalog's reasons in its order, without a reason this build cannot send.
    @Test func theCatalogKeepsTheReasonOrderAndDropsUnknownReasons() throws {
        let json = Data(#"[{"value":"SCAM","label":"Arnaque"},{"value":"NEW_REASON","label":"Nouveau"},"#.utf8)
            + Data(#"{"value":"COUNTERFEIT","label":"Contrefaçon"},{"value":"OTHER","label":"Autre"}]"#.utf8)
        let reasons = try JSONDecoder().decode([ReportReasonOption].self, from: json)
        let catalog = Taleed.Catalog(TaleedAPI.Catalog(categories: [], conditions: [], sorts: [], wilayas: [],
                                                       reportReasons: reasons, disputeReasons: [], payoutMethods: []))
        #expect(catalog.reportReasons.map(\.value) == ["SCAM", "COUNTERFEIT", "OTHER"])
        #expect(catalog.reportReasons.first?.label == "Arnaque")
    }
}
