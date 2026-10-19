import Foundation
import Observation

/// Sign up (`POST /auth/sign-up`): first and family name, username, email, password and an optional
/// referral code. On success the member is signed in.
@MainActor
@Observable
final class SignUpViewModel {
    enum Field: Hashable, CaseIterable, Sendable {
        case firstName, lastName, username, email, password, referralCode

        /// The `issues[].path` of the field.
        var issuePath: String {
            switch self {
            case .firstName: "body.firstName"
            case .lastName: "body.lastName"
            case .username: "body.username"
            case .email: "body.email"
            case .password: "body.password"
            case .referralCode: "body.referralCode"
            }
        }
    }

    enum Outcome: Equatable, Sendable {
        /// Signed in: close the sheet and welcome the member by first name.
        case signedUp(firstName: String)
        /// `invite_required`: the request-access form takes over.
        case inviteRequired
        /// The form shows errors.
        case failed
    }

    var firstName = "" { didSet { clearError(.firstName, if: firstName != oldValue) } }
    var lastName = "" { didSet { clearError(.lastName, if: lastName != oldValue) } }
    var username = "" { didSet { clearError(.username, if: username != oldValue) } }
    var email = "" { didSet { clearError(.email, if: email != oldValue) } }
    var password = "" { didSet { clearError(.password, if: password != oldValue) } }
    var referralCode = "" { didSet { clearError(.referralCode, if: referralCode != oldValue) } }

    private(set) var fieldErrors: [Field: AuthFieldError] = [:]
    /// The message above the button (offline, too many attempts, a refused email).
    private(set) var message: FormMessage?
    /// `email_taken`: offer sign-in and a password reset.
    private(set) var offersSignIn = false
    private(set) var isLoading = false

    @ObservationIgnored private let api: AuthApi
    @ObservationIgnored private let session: SessionManager

    init(api: AuthApi, session: SessionManager, referralCode: String? = nil) {
        self.api = api
        self.session = session
        self.referralCode = referralCode ?? ""
    }

    var canSubmit: Bool { !isLoading }

    /// The checks the device can make, in the form's order. Empty when the form can be sent.
    func localErrors() -> [Field: AuthFieldError] {
        var errors: [Field: AuthFieldError] = [:]
        if !AuthValidation.isValidNamePart(firstName) { errors[.firstName] = .nameLength }
        if !AuthValidation.isValidNamePart(lastName) { errors[.lastName] = .nameLength }
        if !AuthValidation.isValidUsername(username) { errors[.username] = .usernameInvalid }
        if !AuthValidation.isValidEmail(email) { errors[.email] = .emailInvalid }
        switch AuthValidation.newPasswordProblem(password) {
        case .tooShort: errors[.password] = .passwordTooShort
        case .tooLong: errors[.password] = .passwordTooLong
        case nil: break
        }
        return errors
    }

    /// The first field in error, for focus and VoiceOver.
    var firstFieldInError: Field? {
        Field.allCases.first { fieldErrors[$0] != nil }
    }

    var form: SignUpForm {
        SignUpForm(
            firstName: AuthValidation.trimmed(firstName),
            lastName: AuthValidation.trimmed(lastName),
            username: AuthValidation.trimmed(username),
            email: AuthValidation.trimmed(email),
            password: password,
            referralCode: AuthValidation.referralCodeToSend(referralCode)
        )
    }

    func submit() async -> Outcome {
        guard canSubmit else { return .failed }
        message = nil
        offersSignIn = false
        fieldErrors = localErrors()
        guard fieldErrors.isEmpty else { return .failed }

        isLoading = true
        defer { isLoading = false }
        let form = self.form
        do {
            let (token, user) = try await api.signUp(form)
            session.didAuthenticate(token: token, user: user)
            return .signedUp(firstName: form.firstName)
        } catch {
            return handle(error)
        }
    }

    private func handle(_ error: ApiError) -> Outcome {
        switch error.code {
        case .inviteRequired:
            return .inviteRequired
        case .invalidUsername:
            fieldErrors[.username] = .usernameInvalid
        case .usernameTaken:
            fieldErrors[.username] = .usernameTaken
        case .emailTaken:
            fieldErrors[.email] = .emailTaken
            offersSignIn = true
        case .passwordTooShort:
            fieldErrors[.password] = .passwordTooShort
        case .passwordTooLong:
            fieldErrors[.password] = .passwordTooLong
        case .invalidRequest where !error.issues.isEmpty:
            for field in Field.allCases where error.issue(at: field.issuePath) != nil {
                fieldErrors[field] = localErrors()[field] ?? .invalid
            }
            if fieldErrors.isEmpty { message = .error(error) }
        default:
            message = Self.message(for: error)
        }
        return .failed
    }

    static func message(for error: ApiError) -> FormMessage {
        switch error {
        // The account may have been created anyway (api-guide.md, Retrying): the website's
        // "the connection seems slow, try signing in".
        case .network: .key(.authErrorTimeout)
        // `forbidden`: an email that may not sign up again. The API refuses it without saying why, and
        // the website shows its generic error (register-form.tsx).
        case .server, .unknown: .key(.authErrorGeneric)
        case let .failed(failure) where failure.code == .forbidden: .key(.authErrorGeneric)
        default: .error(error)
        }
    }

    private func clearError(_ field: Field, if changed: Bool) {
        guard changed else { return }
        fieldErrors[field] = nil
        if field == .email { offersSignIn = false }
    }
}
