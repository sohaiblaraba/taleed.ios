import Foundation
import Observation

// MARK: - Username

/// The username card (screens.md §7 G16 "Username card"; website `username-form.tsx`): while
/// `usernameNextChangeAt` is ahead the field is replaced by the date; otherwise the new name is checked
/// on the device (the rule, the same name), then `POST /me/username`.
@MainActor
@Observable
final class UsernameSettingsViewModel {
    enum FieldError: Equatable {
        /// `usernameRuleHint`.
        case rule
        /// `usernameSameError`, without a request.
        case same
        /// `usernameTakenError`.
        case taken
        /// `username_cooldown`: the date when known.
        case cooldown(Date?)
    }

    enum Notice: Equatable {
        /// "Vous êtes désormais @{username}."
        case changed(String)
        case error(ApiError)
    }

    var typed = "" {
        didSet { if typed != oldValue { fieldError = nil } }
    }

    private(set) var fieldError: FieldError?
    private(set) var isSending = false
    var notice: Notice?

    @ObservationIgnored private let api: AccountApi
    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let now: () -> Date

    init(api: AccountApi, store: AccountStore, now: @escaping () -> Date = { .now }) {
        self.api = api
        self.store = store
        self.now = now
    }

    var profile: AccountProfile? { store.profile }

    /// The date of the next possible change while the cooldown runs.
    var lockedUntil: Date? {
        guard let profile, profile.usernameLocked(at: now()) else { return nil }
        return profile.usernameNextChangeAt
    }

    var canSubmit: Bool { !isSending && UsernameCheck(typed: typed, current: profile?.username) != .empty }

    func submit() async {
        guard !isSending else { return }
        switch UsernameCheck(typed: typed, current: profile?.username) {
        case .empty: return
        case .invalid: fieldError = .rule
        case .same: fieldError = .same
        case let .ready(username): await send(username)
        }
    }

    private func send(_ username: String) async {
        isSending = true
        defer { isSending = false }
        do {
            let profile = try await api.changeUsername(username)
            store.apply(profile)
            typed = ""
            notice = .changed(profile.username ?? username)
        } catch {
            switch error.code {
            case .usernameTaken?: fieldError = .taken
            case .invalidRequest?: fieldError = .rule
            case .usernameCooldown?:
                // Changed elsewhere meanwhile: the account gives the date, and the field gives way to it.
                await store.reload()
                fieldError = .cooldown(store.profile?.usernameNextChangeAt)
            default: notice = .error(error)
            }
        }
    }
}

// MARK: - Email

/// The email card (screens.md §7 G16 "Email card"; website `email-form.tsx`): the address with its badge,
/// "send the link again" while it is not verified, and the change, which sends a link to the new address
/// (`POST /me/email` always answers `204`). Both send an email: from a button only, never repeated.
@MainActor
@Observable
final class EmailSettingsViewModel {
    enum FieldError: Equatable {
        case invalid
        /// `emailSameError`.
        case same
    }

    var typed = "" {
        didSet { if typed != oldValue { fieldError = nil } }
    }

    private(set) var fieldError: FieldError?
    /// "Lien de confirmation envoyé à {email}…", inline.
    private(set) var sentTo: String?
    /// "Email de vérification envoyé…" replaces the button.
    private(set) var resent = false
    private(set) var isSending = false
    private(set) var isResending = false
    var notice: ApiError?

    @ObservationIgnored private let api: AccountApi
    @ObservationIgnored private let store: AccountStore

    init(api: AccountApi, store: AccountStore) {
        self.api = api
        self.store = store
    }

    var profile: AccountProfile? { store.profile }

    var canSubmit: Bool {
        guard let profile, !isSending else { return false }
        return EmailCheck(typed: typed, current: profile.email) != .empty
    }

    func submit() async {
        guard let profile, !isSending else { return }
        switch EmailCheck(typed: typed, current: profile.email) {
        case .empty: return
        case .invalid: fieldError = .invalid
        case .same: fieldError = .same
        case let .ready(email): await send(email, current: profile.email)
        }
    }

    private func send(_ email: String, current: String) async {
        isSending = true
        defer { isSending = false }
        do {
            try await api.changeEmail(email)
            sentTo = email
            typed = ""
        } catch {
            if error.code == .invalidRequest, error.issue(at: "body.newEmail") != nil {
                // The API refuses the current address on `body.newEmail`.
                fieldError = email == current.lowercased() ? .same : .invalid
            } else {
                notice = error
            }
        }
    }

    /// "Renvoyer l'email de vérification". `invalid_state`: verified meanwhile; the badge follows.
    func resend() async {
        guard !isResending else { return }
        isResending = true
        defer { isResending = false }
        do {
            try await api.resendEmailVerification()
            resent = true
        } catch {
            if error.code == .invalidState {
                await store.reload()
            } else {
                notice = error
            }
        }
    }
}

// MARK: - Password

/// The password card (screens.md §7 G16 "Password card"; website `password-form.tsx`): the current
/// password, the new one (8 to 128) and its confirmation, checked on the device, then `POST /me/password`.
///
/// After a lost answer the same request is never sent again (the old password may be wrong by then):
/// the next tap first sends the new password as both, and `204` means the change went through, while
/// `wrong_password` means it did not and the change is sent again (slice E, Retrying).
@MainActor
@Observable
final class PasswordSettingsViewModel {
    enum Notice: Equatable {
        /// "Mot de passe mis à jour." and the other devices were signed out.
        case changed
        case error(ApiError)
    }

    var form = PasswordForm() {
        didSet {
            for field in [PasswordField.current, .new, .confirm] where fieldValue(field, in: form) != fieldValue(field, in: oldValue) {
                apiErrors[field] = nil
            }
        }
    }

    private(set) var showsDeviceErrors = false
    private(set) var apiErrors: [PasswordField: PasswordFieldError] = [:]
    private(set) var isSending = false
    var notice: Notice?

    @ObservationIgnored private let api: AccountApi
    /// The change whose answer was lost.
    @ObservationIgnored private var unconfirmed: (current: String, new: String)?

    init(api: AccountApi) {
        self.api = api
    }

    var canSubmit: Bool { form.isComplete && !isSending }

    func error(_ field: PasswordField) -> PasswordFieldError? {
        if let error = apiErrors[field] { return error }
        return showsDeviceErrors ? form.errors[field] : nil
    }

    func submit() async {
        guard canSubmit else { return }
        showsDeviceErrors = true
        guard form.errors.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        let current = form.current
        let new = form.new
        do {
            if let unconfirmed, unconfirmed.current == current, unconfirmed.new == new, await wentThrough(new) {
                succeeded()
                return
            }
            try await api.changePassword(current: current, new: new)
            succeeded()
        } catch {
            switch error {
            case .network, .server:
                unconfirmed = (current, new)
                notice = .error(error)
            default:
                unconfirmed = nil
                if error.code == .wrongPassword {
                    apiErrors[.current] = .wrong
                } else if error.code == .invalidRequest, error.issue(at: "body.newPassword") != nil {
                    apiErrors[.new] = AuthValidation.newPasswordProblem(new) == .tooLong ? .tooLong : .tooShort
                } else {
                    notice = .error(error)
                }
            }
        }
    }

    /// The new password as both: `204` means the lost change went through.
    private func wentThrough(_ new: String) async -> Bool {
        do {
            try await api.changePassword(current: new, new: new)
            return true
        } catch {
            return false
        }
    }

    private func succeeded() {
        unconfirmed = nil
        showsDeviceErrors = false
        apiErrors = [:]
        form = PasswordForm()
        notice = .changed
    }

    private func fieldValue(_ field: PasswordField, in form: PasswordForm) -> String {
        switch field {
        case .current: form.current
        case .new: form.new
        case .confirm: form.confirm
        }
    }
}
