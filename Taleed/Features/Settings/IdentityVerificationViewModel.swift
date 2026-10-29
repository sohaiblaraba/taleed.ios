import Foundation
import Observation
import UIKit

/// A field of the legal-name step.
enum VerificationNameField: Hashable, Sendable, CaseIterable {
    case firstName, lastName
}

/// The ID photo picked for the request, kept in memory only until it is sent (app-guidelines, Identity
/// documents): never written anywhere but the uploader's temporary file, which is deleted after the upload.
struct PickedIdDocument: Equatable {
    let id = UUID()
    /// The data as picked (HEIC included); the uploader turns it into JPEG within 1600 × 1600.
    let data: Data
    /// The preview on the tile, scaled down.
    let preview: UIImage

    init?(data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        self.data = data
        preview = image.preparingThumbnail(of: Self.previewSize(for: image.size)) ?? image
    }

    /// A preview at most 1 200 points wide: enough for the 16:9 tile on any phone.
    private static func previewSize(for size: CGSize) -> CGSize {
        PhotoPreparer.fittedSize(size, within: CGSize(width: 1200, height: 1200))
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Why the last "Envoyer ma demande" stopped.
enum VerificationSubmitError: Equatable {
    /// Saving the legal name (`PATCH /me`) failed.
    case name(ApiError)
    /// The photo upload failed: `uploadError`, or the precise reason for a photo the API refuses.
    case upload(ApiError)
    /// `POST /me/verification` failed: `submitError`, with the wait for a rate limit.
    case submit(ApiError)

    var error: ApiError {
        switch self {
        case let .name(error), let .upload(error), let .submit(error): error
        }
    }
}

/// Identity verification (screens.md §2 G17 and §7 G17; website `verification-form.tsx`; slice E).
///
/// `GET /me/verification` decides what shows: NONE and REJECTED the form (REJECTED with the reviewer's
/// note above it), PENDING "under review", VERIFIED the badge with the legal name read-only. The form,
/// in order: the legal name (first word, then the rest, as `GET /me` splits it), which the ID is checked
/// against; one photo of the ID's front, kept in memory; "Envoyer ma demande", enabled once there is a
/// photo. While `features.identityAiReview` is on, the OpenAI consent sheet comes first (slice I).
/// Sending saves a changed name (`PATCH /me`), uploads the photo (`id_document`, just before sending,
/// slice E), then `POST /me/verification` (with the consent answer) → PENDING.
@MainActor
@Observable
final class IdentityVerificationViewModel {
    enum Phase: Equatable {
        case loading
        case failed(ApiError)
        case loaded(IdentityStatus)
    }

    enum Notice: Equatable {
        /// `submitted`: "Demande envoyée — vous serez notifié de la décision."
        case submitted
        /// A picked photo the device cannot read: `uploadError`.
        case unreadablePhoto
        /// A pull-to-refresh that failed: the status on screen may be out of date.
        case refreshFailed(ApiError)
    }

    private(set) var phase: Phase = .loading
    var firstName = "" {
        didSet { if firstName != oldValue { nameApiErrors[.firstName] = nil } }
    }

    var lastName = "" {
        didSet { if lastName != oldValue { nameApiErrors[.lastName] = nil } }
    }

    private(set) var photo: PickedIdDocument?
    private(set) var isSubmitting = false
    private(set) var submitError: VerificationSubmitError?
    /// The device's name checks show once the member tried to send.
    private(set) var showsNameErrors = false
    private(set) var nameApiErrors: [VerificationNameField: ProfileFieldError] = [:]
    var notice: Notice?
    /// The OpenAI consent sheet shows (slice I): set by "Envoyer ma demande" while
    /// `features.identityAiReview` is on. Dismissing the sheet (false) sends nothing.
    var asksAiConsent = false

    @ObservationIgnored private let api: IdentityVerificationApi
    @ObservationIgnored private let account: AccountApi
    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let upload: (Data) async throws(ApiError) -> UploadedPhoto
    /// The key of the picked photo once uploaded: a send that failed after the upload reuses it.
    @ObservationIgnored private var uploadedKey: String?
    /// The names were filled from the account once; later loads keep what the member typed.
    @ObservationIgnored private var namesFilled = false
    @ObservationIgnored private var isLoading = false

    init(api: IdentityVerificationApi, account: AccountApi, store: AccountStore,
         upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto) {
        self.api = api
        self.account = account
        self.store = store
        self.upload = upload
    }

    var status: IdentityStatus? {
        if case let .loaded(status) = phase { return status }
        return nil
    }

    var profile: AccountProfile? { store.profile }

    /// Disabled until there is a photo, and while sending (the website's rule); also while the last send
    /// hit the daily limit (`429`), whose wait shows above the button, until the member picks another photo.
    var canSubmit: Bool { photo != nil && !isSubmitting && status?.acceptsRequest == true && !isRateLimited }

    /// The last send answered `429 rate_limited`.
    var isRateLimited: Bool {
        if case let .submit(error) = submitError, case .rateLimited = error { return true }
        return false
    }

    /// The error under a name field: the API's refusal first, then the device's check once the member tried.
    func nameError(_ field: VerificationNameField) -> ProfileFieldError? {
        if let error = nameApiErrors[field] { return error }
        guard showsNameErrors else { return nil }
        return Self.nameErrors(firstName: firstName, lastName: lastName)[field]
    }

    /// 2 to 30 characters each, as sign-up and the profile card.
    nonisolated static func nameErrors(firstName: String, lastName: String) -> [VerificationNameField: ProfileFieldError] {
        var errors: [VerificationNameField: ProfileFieldError] = [:]
        if !AuthValidation.isValidNamePart(firstName) { errors[.firstName] = .nameLength }
        if !AuthValidation.isValidNamePart(lastName) { errors[.lastName] = .nameLength }
        return errors
    }

    /// `PATCH /me` for the name: only the parts that differ from the account (spaces aside).
    nonisolated static func nameChanges(firstName: String, lastName: String, saved: AccountProfile) -> ProfileChanges {
        var changes = ProfileChanges()
        if !AccountRules.sameName(firstName, saved.firstName) { changes.firstName = AuthValidation.trimmed(firstName) }
        if !AccountRules.sameName(lastName, saved.lastName) { changes.lastName = AuthValidation.trimmed(lastName) }
        return changes
    }

    // MARK: Loading

    /// The account (for the name) and the status. Again with each call: back from a notification, the
    /// status may have changed.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if status == nil { phase = .loading }
        await store.loadIfNeeded()
        guard store.profile != nil else {
            // No session yet (a link during launch): keep loading; the screen loads again with it.
            if let error = store.loadError, status == nil { phase = .failed(error) }
            return
        }
        do {
            apply(try await api.verification(automatic: false))
        } catch {
            if status == nil { phase = .failed(error) }
        }
    }

    func retry() async {
        if store.profile == nil { await store.retry() }
        await load()
    }

    /// Back in the foreground (`automatic`, quiet) or pulled to refresh: a failure keeps what is on screen,
    /// and a pull says so (as Wallet), so "nothing changed" and "could not check" differ (screens.md §0.6).
    func refresh(automatic: Bool) async {
        guard status != nil, !isSubmitting else {
            if status == nil { await load() }
            return
        }
        do {
            apply(try await api.verification(automatic: automatic))
        } catch {
            guard !Task.isCancelled, !automatic else { return }
            notice = .refreshFailed(error)
        }
    }

    private func apply(_ status: IdentityStatus) {
        phase = .loaded(status)
        if !status.acceptsRequest { clearPhoto() }
        fillNamesIfNeeded()
        // A decision (or a removed badge) also changes `isVerified`, the name lock and the profile badge.
        if let profile = store.profile, profile.isVerified != (status == .verified) {
            Task { await store.reload(automatic: true) }
        }
    }

    private func fillNamesIfNeeded() {
        guard !namesFilled, let profile = store.profile else { return }
        namesFilled = true
        firstName = profile.firstName
        lastName = profile.lastName
    }

    // MARK: The photo

    func photoPicked(_ data: Data) {
        guard let picked = PickedIdDocument(data: data) else {
            notice = .unreadablePhoto
            return
        }
        photo = picked
        uploadedKey = nil
        submitError = nil
    }

    func removePhoto() {
        guard !isSubmitting else { return }
        clearPhoto()
        submitError = nil
    }

    private func clearPhoto() {
        photo = nil
        uploadedKey = nil
    }

    // MARK: Sending

    /// "Envoyer ma demande". With `identityAiReview` (slice I), the consent sheet first, at every sending
    /// (a resubmission after a refusal included); without it, the request at once, with no `aiConsent`.
    func submitTapped(identityAiReview: Bool) async {
        guard canSubmit, store.profile != nil else { return }
        showsNameErrors = true
        guard Self.nameErrors(firstName: firstName, lastName: lastName).isEmpty else { return }
        if identityAiReview {
            asksAiConsent = true
        } else {
            await submit(aiConsent: nil)
        }
    }

    /// The consent sheet's answer: "Accepter et continuer" (true) or "Continuer sans vérification
    /// automatique" (false, the team reviews the ID by hand). The sheet closes and the request goes out.
    func answerAiConsent(_ agreed: Bool) async {
        guard asksAiConsent else { return }
        asksAiConsent = false
        await submit(aiConsent: agreed)
    }

    private func submit(aiConsent: Bool?) async {
        guard canSubmit, let photo, let profile = store.profile else { return }
        showsNameErrors = true
        guard Self.nameErrors(firstName: firstName, lastName: lastName).isEmpty else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        guard await saveNameIfChanged(profile) else { return }
        await send(photo, aiConsent: aiConsent, uploadAgainOnRefusal: true)
    }

    /// The ID is checked against the account's name: a changed one is saved first.
    private func saveNameIfChanged(_ profile: AccountProfile) async -> Bool {
        let changes = Self.nameChanges(firstName: firstName, lastName: lastName, saved: profile)
        guard !changes.isEmpty else { return true }
        do {
            let updated = try await account.updateProfile(changes)
            store.apply(updated)
            firstName = updated.firstName
            lastName = updated.lastName
            return true
        } catch {
            switch error.code {
            case .nameLocked?:
                // Verified meanwhile: the section shows it.
                await reloadAfterRefusal()
            case .invalidRequest? where !error.issues.isEmpty:
                for issue in error.issues {
                    switch issue.path {
                    case "body.firstName": nameApiErrors[.firstName] = .invalid
                    case "body.lastName": nameApiErrors[.lastName] = .invalid
                    default: submitError = .name(error)
                    }
                }
            default:
                submitError = .name(error)
            }
            return false
        }
    }

    private func send(_ photo: PickedIdDocument, aiConsent: Bool?, uploadAgainOnRefusal: Bool) async {
        let key: String
        if let uploadedKey {
            key = uploadedKey
        } else {
            do {
                #if DEBUG
                try VerificationDebugFailures.fail(.upload)
                #endif
                key = try await upload(photo.data).key
                // Still the same photo (the member cannot change it while sending).
                if self.photo == photo { uploadedKey = key }
            } catch {
                submitError = .upload(error)
                return
            }
        }
        do {
            let status = try await api.submitVerification(documentKey: key, aiConsent: aiConsent)
            apply(status)
            clearPhoto()
            notice = .submitted
        } catch {
            switch error.code {
            case .invalidState?:
                // Already under review or verified, or the first answer was lost: reload, no error.
                await reloadAfterRefusal()
            case .invalidRequest?:
                // The key is not an uploaded ID document (an unused upload expires after 24 hours): upload again.
                uploadedKey = nil
                if uploadAgainOnRefusal {
                    await send(photo, aiConsent: aiConsent, uploadAgainOnRefusal: false)
                } else {
                    submitError = .upload(error)
                }
            default:
                submitError = .submit(error)
            }
        }
    }

    private func reloadAfterRefusal() async {
        do {
            apply(try await api.verification(automatic: false))
        } catch {
            submitError = .submit(error)
        }
    }
}
