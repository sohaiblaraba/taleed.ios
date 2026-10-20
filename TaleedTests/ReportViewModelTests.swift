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

    /// The field stops at 2 000 characters (`TaleedTextArea.maxLength`), so the model holds what the
    /// field shows; longer details (never from the field) are not sent.
    @Test func detailsOver2000AreNotSentAndScreenshotsStopAt3() async {
        let model = model()
        model.reason = "SCAM"
        model.details = String(repeating: "a", count: 2001)
        #expect(model.isDetailsTooLong)
        #expect(!model.canSubmit)
        #expect(await model.submit() == nil)
        model.details = String(repeating: "a", count: 2000)
        #expect(model.canSubmit)
        for _ in 0..<4 { await model.addEvidence(Data()) }
        #expect(model.evidence.count == 3)
        #expect(!model.canAddEvidence)
    }

    /// A failed screenshot is never left out without a word: Send waits until it is removed (413: the
    /// same photo cannot be sent again, so no retry).
    @Test func aFailedUploadBlocksSendUntilRemoved() async {
        let model = model(upload: .failure(apiError(413, "file_too_large")))
        model.reason = "SPAM"
        await model.addEvidence(Data())
        #expect(model.evidence.first?.error != nil)
        #expect(model.evidence.first?.canRetry == false)
        #expect(model.evidence.first?.data == nil)
        #expect(model.hasFailedEvidence)
        #expect(!model.canSubmit)
        #expect(await model.submit() == nil)
        model.removeEvidence(model.evidence[0].id)
        #expect(model.canSubmit)
        #expect(await model.submit() == .sent)
        #expect(api.reports.first?.evidenceKeys == [])
    }

    /// Offline, a 5xx or a 429: the tile keeps the photo and sends it again.
    @Test func aScreenshotThatFailedOfflineCanBeSentAgain() async {
        var answers: [Result<UploadedPhoto, Taleed.ApiError>] = [.failure(.network), .success(Self.uploaded)]
        let model = ReportViewModel(target: .listing(id: "l1"), api: api, upload: { _ throws(Taleed.ApiError) in
            try answers.removeFirst().get()
        })
        model.reason = "SCAM"
        await model.addEvidence(Data([1, 2, 3]))
        #expect(model.evidence.first?.canRetry == true)
        #expect(!model.canSubmit)
        await model.retryEvidence(model.evidence[0].id)
        #expect(model.evidence.first?.key == "reports/k1")
        #expect(model.evidence.first?.data == nil)
        #expect(model.canSubmit)
        #expect(await model.submit() == .sent)
        #expect(api.reports.first?.evidenceKeys == ["reports/k1"])
    }

    /// A picked photo gets its tile at once, before the library hands it over: Send stays off.
    @Test func aPickedPhotoBlocksSendBeforeItsDataArrives() async {
        let model = model()
        model.reason = "SCAM"
        let ids = model.reserveEvidence(5)
        #expect(ids.count == 3)
        #expect(model.evidence.count == 3)
        #expect(model.isUploading)
        #expect(!model.canSubmit)
        #expect(!model.canAddEvidence)
        await model.upload(ids[0], data: Data())
        model.markUnreadable(ids[1])
        model.removeEvidence(ids[2])
        // Removed while the library loaded it: the late data is ignored.
        await model.upload(ids[2], data: Data())
        #expect(model.evidence.count == 2)
        #expect(!model.canSubmit)
        model.removeEvidence(ids[1])
        #expect(model.canSubmit)
        #expect(await model.submit() == .sent)
        #expect(api.reports.first?.evidenceKeys == ["reports/k1"])
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

    @Test func anUnreadablePhotoIsAFailedTileThatCountsUntilRemoved() async {
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
        #expect(model.evidence.first?.canRetry == false)
        #expect(!model.canSubmit)
        model.removeEvidence(model.evidence[0].id)
        #expect(model.canAddEvidence)
        #expect(await model.submit() == .sent)
        #expect(api.reports.first?.evidenceKeys == ["reports/k1", "reports/k1"])
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

    /// The field cuts at 2 000 UTF-16 units, as the API counts them, keeping the start of a paste.
    @Test func theDetailsFieldCapCountsUTF16Units() {
        let max = ReportViewModel.maxDetailsLength
        #expect(TaleedTextArea.capped(String(repeating: "😀", count: 1001), maxLength: max)?.utf16.count == 2000)
        let pasted = String(repeating: "x", count: 1995) + "ABCDEFGHIJ"
        #expect(TaleedTextArea.capped(pasted, maxLength: max) == String(repeating: "x", count: 1995) + "ABCDE")
        #expect(TaleedTextArea.capped(String(repeating: "x", count: 2000), maxLength: max) == nil)
        #expect(TaleedTextArea.capped(pasted, maxLength: nil) == nil)
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
