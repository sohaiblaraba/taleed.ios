import AuthenticationServices
import Foundation
import Observation

/// "Continue with Apple" and "Continue with Google" on the sign-in and sign-up forms (slice G, Signing in):
/// a fresh nonce for each attempt, the provider's sheet, then `POST /auth/social`.
@MainActor
@Observable
final class SocialSignInViewModel {
    enum Outcome: Equatable, Sendable {
        /// Signed in: close the sheet.
        case signedIn
        /// `403 banned`: the suspended screen replaces the shell, the sheet closes.
        case suspended
        /// A new member: the finish step.
        case profileRequired(SocialProfile)
        /// `invite_required`: the request-access form, as for email sign-up.
        case inviteRequired
        /// The member closed the provider's sheet, or the form shows a message.
        case stayed
    }

    /// The provider whose sign-in is on its way; its button shows the spinner, both buttons are disabled.
    private(set) var pending: SocialProviderKind?
    /// The message under the buttons.
    private(set) var message: FormMessage?

    @ObservationIgnored private let api: AuthApi
    @ObservationIgnored private let session: SessionManager
    @ObservationIgnored private let google: (any GoogleSignInClient)?
    @ObservationIgnored private let onFeatureDisabled: (SocialProviderKind) -> Void
    /// The raw nonce of the Apple attempt in progress (memory only).
    @ObservationIgnored private var appleNonce: String?

    init(api: AuthApi, session: SessionManager, google: (any GoogleSignInClient)?,
         onFeatureDisabled: @escaping (SocialProviderKind) -> Void = { _ in }) {
        self.api = api
        self.session = session
        self.google = google
        self.onFeatureDisabled = onFeatureDisabled
    }

    var isLoading: Bool { pending != nil }

    func clearMessage() {
        message = nil
    }

    // MARK: Google

    func signInWithGoogle() async -> Outcome {
        guard !isLoading, let google else { return .stayed }
        message = nil
        pending = .google
        defer { pending = nil }
        return await finish(await google.signIn(nonce: SocialNonce.make()))
    }

    // MARK: Apple

    /// `SignInWithAppleButton`'s request: a new nonce for this attempt.
    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = SocialNonce.make()
        appleNonce = nonce
        message = nil
        AppleSignIn.configure(request, nonce: nonce)
    }

    /// `SignInWithAppleButton`'s completion.
    func completeApple(_ completion: Result<ASAuthorization, any Error>) async -> Outcome {
        guard let nonce = appleNonce else { return .stayed }
        appleNonce = nil
        return await completeApple(AppleSignIn.result(of: completion, nonce: nonce))
    }

    func completeApple(_ result: SocialProviderResult) async -> Outcome {
        guard !isLoading else { return .stayed }
        pending = .apple
        defer { pending = nil }
        return await finish(result)
    }

    // MARK: The answer

    private func finish(_ result: SocialProviderResult) async -> Outcome {
        switch result {
        case .canceled:
            return .stayed
        case .failed:
            message = .key(.authSocialErrorFailed)
            return .stayed
        case let .credential(credential):
            return await send(credential)
        }
    }

    /// `POST /auth/social`, and what it means for the form.
    func send(_ credential: SocialCredential) async -> Outcome {
        do {
            switch try await api.socialSignIn(credential) {
            case let .session(token, user):
                session.didAuthenticate(token: token, user: user)
                return .signedIn
            case let .profileRequired(profile):
                return .profileRequired(profile)
            case let .suspended(token):
                session.didSignInSuspended(token: token)
                return .suspended
            }
        } catch {
            switch error.code {
            case .banned:
                // An older server's `banned` without a token: the suspended screen with the contacts only.
                session.didSignInSuspended(token: nil)
                return .suspended
            case .inviteRequired:
                return .inviteRequired
            case .featureDisabled:
                onFeatureDisabled(credential.provider)
            default:
                break
            }
            message = Self.messageKey(for: error).map(FormMessage.key)
            return .stayed
        }
    }

    /// The message of a failed `POST /auth/social` (slice G, The answer).
    nonisolated static func messageKey(for error: ApiError) -> L10nKey? {
        if error == .network { return .commonErrorNetwork }
        switch error.code {
        case .banned: return nil
        case .socialEmailUnverified: return .authSocialErrorEmailUnverified
        case .inviteRequired: return .authSocialErrorInviteRequired
        case .forbidden: return .authSocialErrorRefused
        case .featureDisabled: return .authSocialErrorDisabled
        case .rateLimited: return .authSocialErrorRateLimited
        // `social_token_invalid`, `invalid_request`, a 5xx, an unknown answer: offer to try again.
        default: return .authSocialErrorFailed
        }
    }
}
