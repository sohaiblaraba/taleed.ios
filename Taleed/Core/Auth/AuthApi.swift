import Foundation
import TaleedAPI

/// What the sign-up form sends (`POST /auth/sign-up`). Text is already trimmed.
struct SignUpForm: Equatable, Sendable {
    var firstName: String
    var lastName: String
    var username: String
    var email: String
    var password: String
    /// Sent as typed (slice F, Referral codes: the API ignores a malformed code); nil when empty.
    var referralCode: String?
}

/// What the request-access form sends (`POST /access-requests`). Text is already trimmed.
struct AccessRequestForm: Equatable, Sendable {
    /// First and family name joined by a space, as on the website.
    var name: String
    var email: String
    var phone: String?
    var message: String?
    var referralCode: String?
}

/// The sign-up, password reset and access request calls (G1). Sign-in and sign-out are in
/// `TaleedApi`, because the session needs them.
@MainActor
protocol AuthApi: AnyObject {
    /// `POST /auth/sign-up`: the new session.
    func signUp(_ form: SignUpForm) async throws(ApiError) -> (token: String, user: User)
    /// `POST /auth/forgot-password`. Always `204`, whether or not an account uses the email.
    func requestPasswordReset(email: String) async throws(ApiError)
    /// `POST /access-requests` (invite-only period).
    func requestAccess(_ form: AccessRequestForm) async throws(ApiError)
    /// `POST /auth/social` with a Google or Apple ID token (slice G). A suspended member's `banned` with a
    /// token answers `.suspended`; without a token it throws `.banned`.
    func socialSignIn(_ credential: SocialCredential) async throws(ApiError) -> SocialSignInAnswer
    /// `POST /auth/social/complete`: the finish step of a new member, the new session.
    func completeSocialSignUp(_ form: SocialSignUpForm) async throws(ApiError) -> (token: String, user: User)
}

/// The limits of the auth forms, from the contract (screens.md §0.1: the generated `…Rule`
/// constants, never their `pattern`).
enum AuthRules {
    static let emailMaxLength = SignUpRequest.emailRule.maxLength ?? 255
    static let passwordMinLength = SignUpRequest.passwordRule.minLength ?? 8
    static let passwordMaxLength = SignUpRequest.passwordRule.maxLength ?? 128
    static let signInPasswordMaxLength = SignInRequest.passwordRule.maxLength ?? 128
    static let namePartMinLength = SignUpRequest.firstNameRule.minLength ?? 2
    static let namePartMaxLength = SignUpRequest.firstNameRule.maxLength ?? 30
    /// `^[a-zA-Z0-9][a-zA-Z0-9._-]{2,29}$` (`src/lib/username.ts`): 3 to 30 characters.
    static let usernameMinLength = 3
    static let usernameMaxLength = 30
    /// The field takes 8 characters, as the website's (`maxLength={8}`).
    static let referralCodeFieldLength = 8
    static let accessNameMaxLength = AccessRequestCreate.nameRule.maxLength ?? 120
    static let phoneMaxLength = AccessRequestCreate.phoneRule.maxLength ?? 30
    static let messageMaxLength = AccessRequestCreate.messageRule.maxLength ?? 1000
}

extension GeneratedTaleedApi: AuthApi {
    func signUp(_ form: SignUpForm) async throws(ApiError) -> (token: String, user: User) {
        let request = SignUpRequest(firstName: form.firstName, lastName: form.lastName, username: form.username,
                                    email: form.email, password: form.password, referralCode: form.referralCode)
        // A repeated sign-up answers `email_taken` (api-guide.md, Retrying): never repeat it on its own.
        let auth = try await caller.call(.write) { try await AuthAPI.signUp(signUpRequest: request, apiConfiguration: $0) }
        return (auth.token, User(auth.user))
    }

    func requestPasswordReset(email: String) async throws(ApiError) {
        let request = PasswordResetRequest(email: email)
        // Harmless when repeated, but each call may send an email: the member retries from the button.
        try await caller.call(.write) {
            try await AuthAPI.requestPasswordReset(passwordResetRequest: request, apiConfiguration: $0)
        }
    }

    func requestAccess(_ form: AccessRequestForm) async throws(ApiError) {
        let request = AccessRequestCreate(name: form.name, email: form.email, phone: form.phone, message: form.message,
                                          referralCode: form.referralCode)
        try await caller.call(.write) {
            try await AuthAPI.createAccessRequest(accessRequestCreate: request, apiConfiguration: $0)
        }
    }

    func socialSignIn(_ credential: SocialCredential) async throws(ApiError) -> SocialSignInAnswer {
        let provider: SocialProvider = credential.provider == .apple ? .apple : .google
        let request = SocialSignInRequest(provider: provider, idToken: credential.idToken, nonce: credential.nonce,
                                          authorizationCode: credential.authorizationCode,
                                          firstName: credential.firstName, lastName: credential.lastName)
        // Never repeated on its own: after a lost answer the member signs in with the provider again, for a
        // fresh token and nonce (slice G, Retrying).
        return try await caller.call(.write) { configuration -> SocialSignInAnswer in
            do {
                let result = try await AuthAPI.socialSignIn(socialSignInRequest: request, apiConfiguration: configuration)
                return try SocialSignInAnswer(result)
            } catch let error as ErrorResponse {
                if case let .suspended(token)? = SignInAnswer.suspended(from: error) { return .suspended(token: token) }
                throw error
            }
        }
    }

    func completeSocialSignUp(_ form: SocialSignUpForm) async throws(ApiError) -> (token: String, user: User) {
        let request = SocialSignUpRequest(signupToken: form.signupToken, firstName: form.firstName, lastName: form.lastName,
                                          username: form.username, referralCode: form.referralCode)
        // The token is single-use: a repeat answers `social_signup_expired` (slice G, Retrying).
        let auth = try await caller.call(.write) {
            try await AuthAPI.completeSocialSignUp(socialSignUpRequest: request, apiConfiguration: $0)
        }
        return (auth.token, User(auth.user))
    }
}

extension SocialSignInAnswer {
    /// Decodes `status` tolerantly: an unknown status, or one without its object, is a bug to report, not a
    /// crash. It throws an `ErrorResponse` that `ApiError` reads as an unknown `200`.
    init(_ result: SocialSignInResult) throws {
        switch result.status {
        case .signedIn:
            if let session = result.session {
                self = .session(token: session.token, user: User(session.user))
                return
            }
        case .profileRequired:
            if let profile = result.profile {
                self = .profileRequired(SocialProfile(
                    signupToken: profile.signupToken,
                    expiresAt: profile.expiresAt,
                    email: profile.suggested.email,
                    username: profile.suggested.username,
                    firstName: profile.suggested.firstName,
                    lastName: profile.suggested.lastName,
                    referralCode: profile.suggested.referralCode
                ))
                return
            }
        case .unknownDefaultOpenApi:
            break
        }
        throw ErrorResponse.error(200, nil, nil, DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "POST /auth/social answered an unknown status")))
    }
}
