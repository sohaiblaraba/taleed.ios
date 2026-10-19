import Foundation
@testable import Taleed
import Testing

// MARK: - Dispute form

@MainActor
struct DisputeFormViewModelTests {
    @Test func theWebsitesDefaultReason() {
        let model = DisputeFormViewModel(orderId: "o1", api: FakeOrdersApi(), upload: uploadOK)
        model.setReasons(disputeReasons)
        #expect(model.reason == "NOT_RECEIVED")
        model.reason = "DAMAGED"
        model.setReasons(disputeReasons)
        #expect(model.reason == "DAMAGED")
    }

    @Test func theDescriptionNeedsTenCharacters() {
        let model = DisputeFormViewModel(orderId: "o1", api: FakeOrdersApi(), upload: uploadOK)
        model.setReasons(disputeReasons)
        model.description = "  court   "
        #expect(!model.canSubmit(reasons: disputeReasons))
        model.description = "Jamais reçu le colis"
        #expect(model.canSubmit(reasons: disputeReasons))
    }

    @Test func theDescriptionStopsAtTheLimit() {
        let model = DisputeFormViewModel(orderId: "o1", api: FakeOrdersApi(), upload: uploadOK)
        model.description = String(repeating: "a", count: 2100)
        #expect(model.description.utf16.count == DisputeFormViewModel.maxDescription)
    }

    @Test func aReasonThatNeedsEvidenceWaitsForAPhoto() async {
        let model = DisputeFormViewModel(orderId: "o1", api: FakeOrdersApi(), upload: uploadOK)
        model.setReasons(disputeReasons)
        model.reason = "DAMAGED"
        model.description = "La couture est déchirée."
        #expect(model.needsEvidence(in: disputeReasons))
        #expect(!model.canSubmit(reasons: disputeReasons))
        await model.photos.add(Data([0x1]))
        #expect(model.photos.keys.count == 1)
        #expect(model.canSubmit(reasons: disputeReasons))
    }

    @Test func aFailedPhotoDoesNotCount() async {
        let model = DisputeFormViewModel(orderId: "o1", api: FakeOrdersApi(),
                                         upload: { _ throws(Taleed.ApiError) in throw .network })
        model.setReasons(disputeReasons)
        model.reason = "DAMAGED"
        model.description = "La couture est déchirée."
        await model.photos.add(Data([0x1]))
        #expect(model.photos.firstError == .network)
        #expect(!model.canSubmit(reasons: disputeReasons))
    }

    @Test func atMostFourPhotos() async {
        let model = DisputeFormViewModel(orderId: "o1", api: FakeOrdersApi(), upload: uploadOK)
        for _ in 0..<6 { await model.photos.add(Data([0x1])) }
        #expect(model.photos.items.count == 4)
        #expect(model.photos.remaining == 0)
    }

    @Test func submittingSendsTheTrimmedDescriptionAndKeys() async {
        let api = FakeOrdersApi()
        let model = DisputeFormViewModel(orderId: "o1", api: api, upload: uploadOK)
        model.setReasons(disputeReasons)
        model.reason = "DAMAGED"
        model.description = "  La couture est déchirée.  "
        await model.photos.add(Data([0x1]))
        let outcome = await model.submit(reasons: disputeReasons)
        #expect(outcome == .opened(disputeInfo()))
        #expect(api.openedDisputes.first?.reason == "DAMAGED")
        #expect(api.openedDisputes.first?.description == "La couture est déchirée.")
        #expect(api.openedDisputes.first?.keys == ["disputes/2026/10/0123456789abcdef.webp"])
    }

    @Test func anExistingDisputeReloadsTheOrder() async {
        let api = FakeOrdersApi()
        api.disputeResult = .failure(failure(409, .disputeExists))
        let model = DisputeFormViewModel(orderId: "o1", api: api, upload: uploadOK)
        model.setReasons(disputeReasons)
        model.description = "Jamais reçu le colis"
        #expect(await model.submit(reasons: disputeReasons) == .orderChanged(failure(409, .disputeExists)))
        #expect(model.error == nil)
    }

    @Test func otherFailuresStayInTheForm() async {
        let api = FakeOrdersApi()
        api.disputeResult = .failure(.network)
        let model = DisputeFormViewModel(orderId: "o1", api: api, upload: uploadOK)
        model.setReasons(disputeReasons)
        model.description = "Jamais reçu le colis"
        #expect(await model.submit(reasons: disputeReasons) == .failed(.network))
        #expect(model.error == .network)
        #expect(!model.isSending)
    }
}

// MARK: - Dispute thread

@MainActor
struct DisputeThreadViewModelTests {
    @Test func sendingNeedsTextOrAPhoto() async {
        let model = DisputeThreadViewModel(disputeId: "d1", api: FakeOrdersApi(), upload: uploadOK)
        await model.loadIfNeeded()
        #expect(!model.canSend)
        model.draft = "   "
        #expect(!model.canSend)
        model.draft = "Voici une autre photo."
        #expect(model.canSend)
        model.draft = ""
        await model.photos.add(Data([0x1]))
        #expect(model.canSend)
    }

    @Test func aClosedThreadTakesNoMessage() async {
        let api = FakeOrdersApi()
        api.disputeResult = .success(disputeInfo(canPost: false))
        let model = DisputeThreadViewModel(disputeId: "d1", api: api, upload: uploadOK)
        await model.loadIfNeeded()
        model.draft = "Bonjour"
        #expect(!model.canSend)
    }

    @Test func aPostedMessageClearsTheComposer() async {
        let api = FakeOrdersApi()
        let model = DisputeThreadViewModel(disputeId: "d1", api: api, upload: uploadOK)
        await model.loadIfNeeded()
        model.draft = "  Voici une autre photo.  "
        await model.photos.add(Data([0x1]))
        #expect(await model.send())
        #expect(api.posts.first?.body == "Voici une autre photo.")
        #expect(api.posts.first?.keys.count == 1)
        #expect(model.draft.isEmpty)
        #expect(model.photos.items.isEmpty)
        #expect(model.dispute?.messages.count == 2)
        #expect(model.postedCount == 1)
    }

    @Test func aPhotoOnlyMessageSendsNoBody() async {
        let api = FakeOrdersApi()
        let model = DisputeThreadViewModel(disputeId: "d1", api: api, upload: uploadOK)
        await model.loadIfNeeded()
        await model.photos.add(Data([0x1]))
        await model.send()
        #expect(api.posts.first?.body == nil)
    }

    @Test func aFailedPostKeepsTheDraftAndReloads() async {
        let api = FakeOrdersApi()
        api.postResult = .failure(failure(409, .invalidState))
        let model = DisputeThreadViewModel(disputeId: "d1", api: api, upload: uploadOK)
        await model.loadIfNeeded()
        model.draft = "Bonjour"
        #expect(await model.send() == false)
        #expect(model.draft == "Bonjour")
        #expect(model.notice == failure(409, .invalidState))
    }
}

// MARK: - Review form

@MainActor
struct ReviewFormViewModelTests {
    @Test func fiveStarsByDefaultAndClamped() {
        let model = ReviewFormViewModel(orderId: "o1", api: FakeOrdersApi())
        #expect(model.rating == 5)
        model.rating = 9
        #expect(model.rating == 5)
        model.rating = 0
        #expect(model.rating == 1)
        model.rating = 3
        #expect(model.rating == 3)
    }

    @Test func theCommentStopsAtTheLimit() {
        let model = ReviewFormViewModel(orderId: "o1", api: FakeOrdersApi())
        model.comment = String(repeating: "é", count: 1200)
        #expect(model.comment.utf16.count == ReviewFormViewModel.maxComment)
    }

    @Test func anEmptyCommentIsLeftOut() async {
        let api = FakeOrdersApi()
        let model = ReviewFormViewModel(orderId: "o1", api: api)
        model.comment = "   "
        _ = await model.submit()
        #expect(api.reviews.first?.rating == 5)
        #expect(api.reviews.first?.comment == nil)
    }

    @Test func alreadyReviewedReloadsTheOrder() async {
        let api = FakeOrdersApi()
        api.reviewResult = .failure(failure(409, .alreadyReviewed))
        let model = ReviewFormViewModel(orderId: "o1", api: api)
        #expect(await model.submit() == .orderChanged(failure(409, .alreadyReviewed)))
    }

    @Test func otherFailuresStayInTheForm() async {
        let api = FakeOrdersApi()
        api.reviewResult = .failure(.server(status: 500))
        let model = ReviewFormViewModel(orderId: "o1", api: api)
        #expect(await model.submit() == .failed(.server(status: 500)))
        #expect(model.error == .server(status: 500))
    }
}
