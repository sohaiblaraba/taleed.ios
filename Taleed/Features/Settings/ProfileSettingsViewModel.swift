import Foundation
import Observation

/// The profile and billing card (screens.md §7 G16 "Profile card" and "Billing"; website `settings-form.tsx`):
/// the photo (uploaded as soon as it is picked, saved with the form, or removed), the legal name
/// (read-only while verified), the bio, the phone, the wilaya, then the billing details, with one Save:
/// `PATCH /me` with the changed fields, then `PUT /me/billing` with every field. "Paramètres enregistrés."
/// only when both passed; a refused field shows its error under it.
@MainActor
@Observable
final class ProfileSettingsViewModel {
    enum Notice: Equatable {
        case saved
        case error(ApiError)
    }

    var form = ProfileForm()
    /// What the server has: Save is enabled while the form differs from it.
    private(set) var saved: ProfileForm?
    private(set) var loadError: ApiError?
    private(set) var isSaving = false
    private(set) var isUploading = false
    /// The device's checks show once the member tried to save; the API's refusals until the field changes.
    private(set) var showsDeviceErrors = false
    private(set) var apiErrors: [ProfileField: ProfileFieldError] = [:]
    var notice: Notice?
    /// Bumped when a save stopped on a field error: the screen scrolls to the first one.
    private(set) var fieldErrorsShown = 0

    @ObservationIgnored private let api: AccountApi
    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let upload: (Data) async throws(ApiError) -> UploadedPhoto
    @ObservationIgnored private var savedBilling = BillingInfo()

    init(api: AccountApi, store: AccountStore, upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto) {
        self.api = api
        self.store = store
        self.upload = upload
    }

    var profile: AccountProfile? { store.profile }
    /// The identity is verified: the name is read-only (`409 name_locked` otherwise).
    var nameLocked: Bool { profile?.isVerified ?? false }

    var canSave: Bool {
        guard let saved, !isSaving, !isUploading else { return false }
        return form.hasChanges(from: saved, nameLocked: nameLocked)
    }

    /// The photo to show: the one just uploaded, none once removed, or the saved one.
    var avatarURL: URL? {
        switch form.avatar {
        case let .uploaded(_, url): url
        case .removed: nil
        case .unchanged: profile?.avatarURL
        }
    }

    var hasPhoto: Bool { avatarURL != nil }

    /// The first field showing an error, in screen order.
    var firstErrorField: ProfileField? {
        ProfileField.allCases.first { error($0) != nil }
    }

    /// The error under a field: the API's refusal first, then the device's check once the member tried.
    func error(_ field: ProfileField) -> ProfileFieldError? {
        if let error = apiErrors[field] { return error }
        guard showsDeviceErrors else { return nil }
        return form.errors(nameLocked: nameLocked)[field]
    }

    /// The member edited a field: its refusal goes.
    func edited(_ field: ProfileField) {
        apiErrors[field] = nil
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard saved == nil, loadError == nil else { return }
        await load()
    }

    func retry() async {
        loadError = nil
        await load()
    }

    private func load() async {
        if store.profile == nil, let error = await store.reload() {
            loadError = error
            return
        }
        do {
            let billing = try await api.billing()
            guard let profile = store.profile else { return }
            savedBilling = billing
            let loaded = ProfileForm(profile: profile, billing: billing)
            saved = loaded
            form = loaded
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error
        }
    }

    // MARK: Photo

    /// Uploads the picked photo at once (`avatar`, 800 × 800 at most); it is saved with the form.
    func photoPicked(_ data: Data) async {
        isUploading = true
        defer { isUploading = false }
        do {
            let photo = try await upload(data)
            form.avatar = .uploaded(key: photo.key, url: photo.url ?? photo.thumbURL)
            apiErrors[.avatar] = nil
        } catch {
            notice = .error(error)
        }
    }

    /// "Supprimer la photo": `avatarKey: ""` when saved (the website cannot remove one).
    func removePhoto() {
        form.avatar = profile?.avatarURL == nil ? .unchanged : .removed
        apiErrors[.avatar] = nil
    }

    // MARK: Saving

    func save() async {
        guard let saved, !isSaving, !isUploading else { return }
        showsDeviceErrors = true
        guard form.errors(nameLocked: nameLocked).isEmpty else {
            fieldErrorsShown += 1
            return
        }
        isSaving = true
        defer { isSaving = false }

        let changes = form.profileChanges(from: saved, nameLocked: nameLocked)
        if !changes.isEmpty {
            do {
                let profile = try await api.updateProfile(changes)
                store.apply(profile)
                let updated = ProfileForm(profile: profile, billing: savedBilling)
                self.saved = updated
                // The server's values (the phone without its spaces); the billing as typed.
                form.firstName = updated.firstName
                form.lastName = updated.lastName
                form.bio = updated.bio
                form.phone = updated.phone
                form.wilayaId = updated.wilayaId
                form.avatar = .unchanged
            } catch {
                handle(error, issueField: ProfileForm.field(ofProfileIssue:))
                return
            }
        }

        if let current = self.saved, form.billingChanged(from: current) {
            do {
                let billing = try await api.updateBilling(form.billing)
                savedBilling = billing
                guard let profile = store.profile else { return }
                let updated = ProfileForm(profile: profile, billing: billing)
                self.saved = updated
                form = updated
            } catch {
                handle(error, issueField: ProfileForm.field(ofBillingIssue:))
                return
            }
        }
        apiErrors = [:]
        showsDeviceErrors = false
        notice = .saved
    }

    private func handle(_ error: ApiError, issueField: (String) -> ProfileField?) {
        switch error.code {
        case .invalidRequest?:
            let fields = error.issues.compactMap { issue in issueField(issue.path) }
            guard !fields.isEmpty else {
                notice = .error(error)
                return
            }
            for field in fields {
                // The format passed on the device: the server refuses this number (left by a suspended account).
                apiErrors[field] = field == .phone ? .phoneRefused : .invalid
            }
            fieldErrorsShown += 1
        case .nameLocked?:
            // Verified meanwhile: the name freezes; the account says so.
            apiErrors[.firstName] = .nameLocked
            apiErrors[.lastName] = .nameLocked
            if let saved {
                form.firstName = saved.firstName
                form.lastName = saved.lastName
            }
            fieldErrorsShown += 1
            Task { await store.reload() }
        default:
            notice = .error(error)
        }
    }
}
