import Foundation
@testable import Taleed
import TaleedAPI
import Testing
import UIKit

// MARK: - Fakes

@MainActor
final class FakeIdentityVerificationApi: IdentityVerificationApi {
    var statusResults: [Result<IdentityStatus, Taleed.ApiError>] = []
    var status = IdentityStatus.none
    var submitResults: [Result<IdentityStatus, Taleed.ApiError>] = []
    private(set) var loads: [Bool] = []
    private(set) var submittedKeys: [String] = []

    func verification(automatic: Bool) async throws(Taleed.ApiError) -> IdentityStatus {
        loads.append(automatic)
        if !statusResults.isEmpty { return try statusResults.removeFirst().get() }
        return status
    }

    func submitVerification(documentKey: String) async throws(Taleed.ApiError) -> IdentityStatus {
        submittedKeys.append(documentKey)
        if !submitResults.isEmpty { return try submitResults.removeFirst().get() }
        status = .pending
        return .pending
    }
}

/// The uploads of one screen: each call returns a new key, or the next queued error.
@MainActor
final class FakeIdUploads {
    var errors: [Taleed.ApiError?] = []
    private(set) var uploads: [Data] = []

    func upload(_ data: Data) throws(Taleed.ApiError) -> UploadedPhoto {
        uploads.append(data)
        if !errors.isEmpty, let error = errors.removeFirst() { throw error }
        return UploadedPhoto(key: "verification/k\(uploads.count).webp", url: nil, thumbURL: nil)
    }
}

private func photoData() -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 18))
    return renderer.image { context in
        UIColor.blue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
    }.pngData() ?? Data()
}

private func invalidRequest(_ path: String) -> Taleed.ApiError {
    .failed(ApiFailure(status: 400, code: .invalidRequest, issues: [ApiFieldIssue(path: path, message: "Invalid")]))
}

private let invalidState = Taleed.ApiError.failed(ApiFailure(status: 409, code: .invalidState))

// MARK: - Status

struct IdentityStatusTests {
    @Test func theApiStatusMapsToTheSection() {
        #expect(IdentityStatus(IdentityVerification(status: ._none, rejectionNote: nil)) == .none)
        #expect(IdentityStatus(IdentityVerification(status: .pending, rejectionNote: nil)) == .pending)
        #expect(IdentityStatus(IdentityVerification(status: .verified, rejectionNote: nil)) == .verified)
        #expect(IdentityStatus(IdentityVerification(status: .rejected, rejectionNote: " Photo floue ")) == .rejected(note: "Photo floue"))
        // No reason, or only spaces: the sentence without a note.
        #expect(IdentityStatus(IdentityVerification(status: .rejected, rejectionNote: nil)) == .rejected(note: nil))
        #expect(IdentityStatus(IdentityVerification(status: .rejected, rejectionNote: "  ")) == .rejected(note: nil))
        // A status this version does not know: the form; the server decides.
        #expect(IdentityStatus(IdentityVerification(status: .unknownDefaultOpenApi, rejectionNote: nil)) == .none)
    }

    @Test func onlyNoneAndRejectedShowTheForm() {
        #expect(IdentityStatus.none.acceptsRequest)
        #expect(IdentityStatus.rejected(note: "x").acceptsRequest)
        #expect(!IdentityStatus.pending.acceptsRequest)
        #expect(!IdentityStatus.verified.acceptsRequest)
    }

    @Test func theUnknownStatusDecodesTolerantly() throws {
        let data = Data(#"{"status":"EXPIRED","rejectionNote":null}"#.utf8)
        let decoded = try JSONDecoder().decode(IdentityVerification.self, from: data)
        #expect(IdentityStatus(decoded) == .none)
    }
}

struct VerificationNameRulesTests {
    @Test func eachPartHasTwoToThirtyCharacters() {
        #expect(IdentityVerificationViewModel.nameErrors(firstName: "Yacine", lastName: "Kaci").isEmpty)
        let errors = IdentityVerificationViewModel.nameErrors(firstName: " Y ", lastName: String(repeating: "k", count: 31))
        #expect(errors[.firstName] == .nameLength)
        #expect(errors[.lastName] == .nameLength)
    }

    @Test func onlyTheChangedPartIsSaved() {
        let saved = AccountProfile.fixture(firstName: "Nour", lastName: "El Houda Benali")
        #expect(IdentityVerificationViewModel.nameChanges(firstName: "Nour", lastName: "El  Houda Benali ", saved: saved).isEmpty)
        let changes = IdentityVerificationViewModel.nameChanges(firstName: " Nour ", lastName: "Benali", saved: saved)
        #expect(changes == ProfileChanges(lastName: "Benali"))
    }
}

// MARK: - View model

@MainActor
struct IdentityVerificationViewModelTests {
    let api = FakeIdentityVerificationApi()
    let account = FakeAccountApi()
    let uploads = FakeIdUploads()

    private func model(status: IdentityStatus = .none, profile: AccountProfile = .fixture(firstName: "Yacine", lastName: "Kaci"))
        async -> IdentityVerificationViewModel {
        api.status = status
        account.profile = profile
        let (store, _) = await signedInStore(account)
        let uploads = uploads
        let model = IdentityVerificationViewModel(api: api, account: account, store: store) { data throws(Taleed.ApiError) in
            try uploads.upload(data)
        }
        await model.load()
        return model
    }

    @Test func noneShowsTheFormWithTheAccountName() async {
        let model = await model()
        #expect(model.status == IdentityStatus.none)
        #expect(model.firstName == "Yacine")
        #expect(model.lastName == "Kaci")
        // The website: disabled until there is a photo.
        #expect(!model.canSubmit)
        model.photoPicked(photoData())
        #expect(model.canSubmit)
        model.removePhoto()
        #expect(model.photo == nil)
        #expect(!model.canSubmit)
    }

    @Test func sendingUploadsThePhotoThenGoesPending() async {
        let model = await model()
        let data = photoData()
        model.photoPicked(data)
        await model.submit()
        #expect(uploads.uploads == [data])
        #expect(api.submittedKeys == ["verification/k1.webp"])
        #expect(model.status == .pending)
        #expect(model.notice == .submitted)
        // The ID leaves the device's memory, and the form is gone.
        #expect(model.photo == nil)
        #expect(!model.canSubmit)
        // An unchanged name is not saved again.
        #expect(account.profileChanges.isEmpty)
    }

    @Test func aChangedNameIsSavedFirst() async {
        let model = await model()
        model.photoPicked(photoData())
        model.lastName = "Kaci Benali"
        await model.submit()
        #expect(account.profileChanges == [ProfileChanges(lastName: "Kaci Benali")])
        #expect(model.status == .pending)
    }

    @Test func anInvalidNameStopsBeforeAnyRequest() async {
        let model = await model()
        model.photoPicked(photoData())
        model.firstName = "Y"
        await model.submit()
        #expect(model.nameError(.firstName) == .nameLength)
        #expect(model.nameError(.lastName) == nil)
        #expect(uploads.uploads.isEmpty)
        #expect(api.submittedKeys.isEmpty)
        #expect(account.profileChanges.isEmpty)
    }

    @Test func aNameRefusedByTheApiShowsUnderItsField() async {
        let model = await model()
        model.photoPicked(photoData())
        model.firstName = "Yacinou"
        account.updateProfileError = invalidRequest("body.firstName")
        await model.submit()
        #expect(model.nameError(.firstName) == .invalid)
        #expect(uploads.uploads.isEmpty)
        model.firstName = "Yacine2"
        #expect(model.nameError(.firstName) == nil)
    }

    @Test func aLockedNameMeansVerifiedMeanwhile() async {
        let model = await model()
        model.photoPicked(photoData())
        model.firstName = "Yacinou"
        account.updateProfileError = .failed(ApiFailure(status: 409, code: .nameLocked))
        api.status = .verified
        await model.submit()
        #expect(model.status == .verified)
        #expect(model.submitError == nil)
        #expect(model.photo == nil)
        #expect(uploads.uploads.isEmpty)
    }

    @Test func invalidStateReloadsWithoutAnError() async {
        let model = await model()
        model.photoPicked(photoData())
        api.submitResults = [.failure(invalidState)]
        api.status = .pending
        await model.submit()
        #expect(model.status == .pending)
        #expect(model.submitError == nil)
        #expect(model.notice == nil)
        #expect(model.photo == nil)
    }

    @Test func aRefusedKeyIsUploadedAgainOnce() async {
        let model = await model()
        model.photoPicked(photoData())
        api.submitResults = [.failure(invalidRequest("body.documentKey"))]
        await model.submit()
        #expect(uploads.uploads.count == 2)
        #expect(api.submittedKeys == ["verification/k1.webp", "verification/k2.webp"])
        #expect(model.status == .pending)
    }

    @Test func aKeyRefusedTwiceShowsTheUploadError() async {
        let model = await model()
        model.photoPicked(photoData())
        let refusal = invalidRequest("body.documentKey")
        api.submitResults = [.failure(refusal), .failure(refusal)]
        await model.submit()
        #expect(model.submitError == .upload(refusal))
        #expect(model.status == IdentityStatus.none)
        #expect(model.photo != nil)
    }

    @Test func aFailedUploadSendsNothing() async {
        let model = await model()
        model.photoPicked(photoData())
        uploads.errors = [.network]
        await model.submit()
        #expect(model.submitError == .upload(.network))
        #expect(api.submittedKeys.isEmpty)
        #expect(model.canSubmit)
        await model.submit()
        #expect(model.status == .pending)
    }

    /// A send that failed after the upload reuses the key: one upload, and a lost answer comes back as
    /// `invalid_state` on the next tap.
    @Test func aRetryAfterALostSendReusesTheUpload() async {
        let model = await model()
        model.photoPicked(photoData())
        api.submitResults = [.failure(.network)]
        await model.submit()
        #expect(model.submitError == .submit(.network))
        await model.submit()
        #expect(uploads.uploads.count == 1)
        #expect(api.submittedKeys == ["verification/k1.webp", "verification/k1.webp"])
        #expect(model.status == .pending)
    }

    @Test func anotherPhotoIsUploadedAgain() async {
        let model = await model()
        model.photoPicked(photoData())
        api.submitResults = [.failure(.network)]
        await model.submit()
        model.photoPicked(photoData())
        await model.submit()
        #expect(uploads.uploads.count == 2)
    }

    @Test func theDailyLimitShowsTheSubmitErrorWithTheWait() async {
        let model = await model(status: .rejected(note: "Photo floue"))
        model.photoPicked(photoData())
        api.submitResults = [.failure(.rateLimited(retryAfter: 3600))]
        await model.submit()
        #expect(model.submitError == .submit(.rateLimited(retryAfter: 3600)))
        #expect(model.status == .rejected(note: "Photo floue"))
        #expect(model.submitError?.error.rateLimitMinutes == 60)
    }

    @Test func pendingAndVerifiedShowNoForm() async {
        let pending = await model(status: .pending)
        pending.photoPicked(photoData())
        #expect(!pending.canSubmit)
        let verified = await model(status: .verified, profile: .fixture(isVerified: true))
        #expect(verified.status == .verified)
        #expect(!verified.canSubmit)
    }

    @Test func aFailedLoadShowsTheErrorAndRetryLoads() async {
        api.statusResults = [.failure(.network)]
        let model = await model()
        #expect(model.phase == .failed(.network))
        await model.retry()
        #expect(model.status == IdentityStatus.none)
    }

    /// Back in the foreground after the decision: the new status, and the account follows (name lock, badge).
    @Test func aDecisionReloadsTheAccount() async {
        let model = await model(status: .pending)
        let calls = account.accountCalls
        api.status = .verified
        account.profile = .fixture(isVerified: true, firstName: "Yacine", lastName: "Kaci")
        await model.refresh(automatic: true)
        #expect(api.loads.last == true)
        #expect(model.status == .verified)
        await Task.yield()
        for _ in 0..<5 where account.accountCalls == calls { await Task.yield() }
        #expect(account.accountCalls > calls)
    }

    @Test func aFailedRefreshKeepsWhatIsOnScreen() async {
        let model = await model(status: .rejected(note: nil))
        api.statusResults = [.failure(.network)]
        await model.refresh(automatic: true)
        #expect(model.status == .rejected(note: nil))
        // The foreground reload stays quiet.
        #expect(model.notice == nil)
    }

    /// A pull that fails says so, as Wallet (screens.md §0.6), and keeps the status on screen.
    @Test func aFailedPullToRefreshShowsTheError() async {
        let model = await model(status: .pending)
        api.statusResults = [.failure(.network)]
        await model.refresh(automatic: false)
        #expect(api.loads.last == false)
        #expect(model.status == .pending)
        #expect(model.notice == .refreshFailed(.network))
    }

    @Test func theDailyLimitSaysHoursOverAnHour() {
        let error = ApiError.rateLimited(retryAfter: 86_400)
        #expect(error.rateLimitHours == 24)
        #expect(error.message(in: .fr) == "Trop de requêtes. Réessayez dans 24 heures.")
        // An hour reads "1 heure", never "60 minutes" (P4).
        #expect(ApiError.rateLimited(retryAfter: 3600).rateLimitHours == 1)
        #expect(ApiError.rateLimited(retryAfter: 3600).message(in: .fr) == "Trop de requêtes. Réessayez dans 1 heure.")
        #expect(ApiError.rateLimited(retryAfter: 3540).message(in: .fr) == "Trop de requêtes. Réessayez dans 59 minutes.")
    }

    @Test func anUnreadablePhotoIsRefused() async {
        let model = await model()
        model.photoPicked(Data("not an image".utf8))
        #expect(model.photo == nil)
        #expect(model.notice == .unreadablePhoto)
    }
}

// MARK: - Navigation

@MainActor
struct IdentityVerificationRoutingTests {
    @Test func theDecisionsOpenTheSection() {
        #expect(notification("n", type: "VERIFICATION_APPROVED", url: "http://localhost:3000/settings").destination
            == .screen(.identityVerification))
        #expect(notification("n", type: "VERIFICATION_REJECTED", url: "https://taleed.app/ar/settings").destination
            == .screen(.identityVerification))
        // The welcome voucher goes to the wallet, as its link says.
        #expect(notification("n", type: "VERIFICATION_VOUCHER", url: "http://localhost:3000/wallet").destination == .screen(.wallet))
    }

    @Test func theSectionSitsOverSettingsAndNeedsASession() {
        let (tab, stack) = AppRouter.canonicalStack(for: .identityVerification)
        #expect(tab == .profile)
        #expect(stack == [.settings, .identityVerification])
        #expect(AppRoute.identityVerification.requiresSignIn)
    }
}
