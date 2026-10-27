import Foundation
import Observation

/// The finish step after a first Google or Apple sign-in (slice G, The finish step; decision FB-7): first and
/// family name, username and an optional referral code, with the sign-up form's rules, then
/// `POST /auth/social/complete`. The email is shown, not sent. The token stays in memory: when the sheet
/// closes, the member signs in with the provider again.
@MainActor
@Observable
final class FinishSignUpViewModel {
    enum Field: Hashable, CaseIterable, Sendable {
        case firstName, lastName, username, referralCode

        var issuePath: String {
            switch self {
            case .firstName: "body.firstName"
            case .lastName: "body.lastName"
            case .username: "body.username"
            case .referralCode: "body.referralCode"
            }
        }
    }

    enum Outcome: Equatable, Sendable {
        /// The account exists and the member is signed in: welcome them by first name.
        case signedUp(firstName: String)
        /// `social_signup_expired`: back to sign-in, "Continue with Google or Apple again".
        case expired
        /// `email_taken`: an account with this email appeared meanwhile; back to sign-in, where the
        /// provider now answers `signed_in`.
        case emailTaken
        /// `invite_required`: the request-access form.
        case inviteRequired
        /// The form shows errors.
        case failed
    }

    let profile: SocialProfile

    var firstName: String { didSet { clearError(.firstName, if: firstName != oldValue) } }
    var lastName: String { didSet { clearError(.lastName, if: lastName != oldValue) } }
    var username: String { didSet { clearError(.username, if: username != oldValue) } }
    var referralCode: String { didSet { clearError(.referralCode, if: referralCode != oldValue) } }

    private(set) var fieldErrors: [Field: AuthFieldError] = [:]
    /// The message above the button (refused, offline, too many attempts).
    private(set) var message: FormMessage?
    private(set) var isLoading = false

    @ObservationIgnored private let api: AuthApi
    @ObservationIgnored private let session: SessionManager

    /// `linkReferralCode`: the code of an invite link the app opened; it wins over the access request's.
    init(profile: SocialProfile, linkReferralCode: String?, api: AuthApi, session: SessionManager) {
        self.profile = profile
        self.api = api
        self.session = session
        firstName = AuthValidation.limited(profile.firstName ?? "", to: AuthRules.namePartMaxLength)
        lastName = AuthValidation.limited(profile.lastName ?? "", to: AuthRules.namePartMaxLength)
        username = profile.username
        referralCode = linkReferralCode ?? profile.referralCode ?? ""
    }

    /// The checks the device can make, as on the sign-up form.
    func localErrors() -> [Field: AuthFieldError] {
        var errors: [Field: AuthFieldError] = [:]
        if !AuthValidation.isValidNamePart(firstName) { errors[.firstName] = .nameLength }
        if !AuthValidation.isValidNamePart(lastName) { errors[.lastName] = .nameLength }
        switch AuthValidation.usernameProblem(username) {
        case .length: errors[.username] = .usernameLength
        case .start: errors[.username] = .usernameStart
        case .characters: errors[.username] = .usernameCharacters
        case nil: break
        }
        return errors
    }

    var firstFieldInError: Field? {
        Field.allCases.first { fieldErrors[$0] != nil }
    }

    var form: SocialSignUpForm {
        SocialSignUpForm(
            signupToken: profile.signupToken,
            firstName: AuthValidation.trimmed(firstName),
            lastName: AuthValidation.trimmed(lastName),
            username: AuthValidation.trimmed(username),
            referralCode: AuthValidation.referralCodeToSend(referralCode)
        )
    }

    func submit() async -> Outcome {
        guard !isLoading else { return .failed }
        message = nil
        fieldErrors = localErrors()
        guard fieldErrors.isEmpty else { return .failed }

        isLoading = true
        defer { isLoading = false }
        let form = self.form
        do {
            let (token, user) = try await api.completeSocialSignUp(form)
            session.didAuthenticate(token: token, user: user)
            return .signedUp(firstName: form.firstName)
        } catch {
            return handle(error)
        }
    }

    private func handle(_ error: ApiError) -> Outcome {
        switch error.code {
        case .socialSignupExpired:
            return .expired
        case .emailTaken:
            return .emailTaken
        case .inviteRequired:
            return .inviteRequired
        // The token stays valid after a username error: the member changes the name and sends again.
        case .usernameTaken:
            fieldErrors[.username] = .usernameTaken
        case .invalidUsername:
            fieldErrors[.username] = .usernameInvalid
        case .invalidRequest where !error.issues.isEmpty:
            for field in Field.allCases where error.issue(at: field.issuePath) != nil {
                fieldErrors[field] = localErrors()[field] ?? .invalid
            }
            if fieldErrors.isEmpty { message = .key(.authErrorGeneric) }
        default:
            message = Self.messageKey(for: error).map(FormMessage.key)
        }
        return .failed
    }

    /// The message of a failed `POST /auth/social/complete` that keeps the member on the form.
    nonisolated static func messageKey(for error: ApiError) -> L10nKey? {
        if error == .network { return .commonErrorNetwork }
        switch error.code {
        case .forbidden: return .authSocialErrorRefused
        case .rateLimited: return .authSocialErrorRateLimited
        default: return .authErrorGeneric
        }
    }

    private func clearError(_ field: Field, if changed: Bool) {
        guard changed else { return }
        fieldErrors[field] = nil
    }
}
