import Foundation
import Observation

/// Sign in (`POST /auth/sign-in`): email and password.
@MainActor
@Observable
final class SignInViewModel {
    var email = "" {
        didSet { if email != oldValue { emailError = nil } }
    }
    var password = ""
    private(set) var isLoading = false
    private(set) var emailError: AuthFieldError?
    /// The message under the form (wrong password, offline, too many attempts).
    private(set) var message: FormMessage?

    @ObservationIgnored private let session: SessionManager

    init(session: SessionManager) {
        self.session = session
    }

    /// The button works once both fields are filled; the email format is checked on submit.
    var canSubmit: Bool {
        !isLoading && !AuthValidation.trimmed(email).isEmpty && !password.isEmpty
    }

    /// The message key under the form, for the errors that have their own wording.
    var errorKey: L10nKey? {
        if case let .key(key) = message { return key }
        return nil
    }

    /// Returns true when the sheet should close: signed in, or suspended (the suspended screen
    /// replaces the shell).
    func submit() async -> Bool {
        guard canSubmit else { return false }
        message = nil
        guard AuthValidation.isValidEmail(email) else {
            emailError = .emailInvalid
            return false
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await session.signIn(email: AuthValidation.trimmed(email), password: password)
            return true
        } catch {
            message = Self.message(for: error)
            return error == .banned
        }
    }

    static func message(for error: ApiError) -> FormMessage? {
        if error == .banned { return nil }
        // A wait over a minute says how many minutes.
        if error.rateLimitMinutes != nil { return .error(error) }
        if error.issue(at: "body.email") != nil { return .key(.appAuthEmailInvalid) }
        return messageKey(for: error).map(FormMessage.key)
    }

    static func messageKey(for error: ApiError) -> L10nKey? {
        switch error {
        case .invalidCredentials: .authErrorInvalidCredentials
        case .rateLimited: .authErrorRateLimited
        case .network: .commonErrorNetwork
        case .banned: nil
        default: .commonErrorGeneric
        }
    }
}
