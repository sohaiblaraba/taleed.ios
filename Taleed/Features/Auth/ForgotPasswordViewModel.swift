import Foundation
import Observation

/// Forgot password (`POST /auth/forgot-password`). The API always answers `204`, so the screen always
/// says "if an account exists for this email, a link has been sent". The reset itself happens on the
/// website (decision 2).
@MainActor
@Observable
final class ForgotPasswordViewModel {
    var email = "" {
        didSet { if email != oldValue { emailError = nil } }
    }
    private(set) var emailError: AuthFieldError?
    private(set) var message: FormMessage?
    /// The request went through: the neutral confirmation shows.
    private(set) var isSent = false
    private(set) var isLoading = false

    @ObservationIgnored private let api: AuthApi

    init(api: AuthApi, email: String = "") {
        self.api = api
        self.email = email
    }

    var canSubmit: Bool { !isLoading && !AuthValidation.trimmed(email).isEmpty }

    func submit() async {
        guard canSubmit else { return }
        message = nil
        isSent = false
        guard AuthValidation.isValidEmail(email) else {
            emailError = .emailInvalid
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await api.requestPasswordReset(email: AuthValidation.trimmed(email))
            isSent = true
        } catch {
            if error.issue(at: "body.email") != nil {
                emailError = .emailInvalid
            } else {
                message = .error(error)
            }
        }
    }
}
