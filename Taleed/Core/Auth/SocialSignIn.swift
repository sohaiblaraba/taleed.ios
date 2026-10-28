import CryptoKit
import Foundation
import Security

// Sign in with Google and Apple (slice G): the nonce, what the providers give, and what the server answers.

/// The nonce of one sign-in attempt (slice G, The nonce): 32 random bytes, base64url without padding. The app
/// keeps it in memory for that attempt only. Google gets it as is, Apple its SHA-256 in lowercase hex; the
/// server always gets the raw value.
enum SocialNonce {
    static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // `SecRandomCopyBytes` does not fail on iOS; the system generator is the fallback all the same.
            var generator = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// `ASAuthorizationAppleIDRequest.nonce`: the SHA-256 of the raw nonce, in lowercase hex.
    static func sha256Hex(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// The two providers. Apple is offered on iOS only.
enum SocialProviderKind: String, Equatable, Sendable {
    case google, apple
}

/// What a provider's sheet gave, ready for `POST /auth/social`.
struct SocialCredential: Equatable, Sendable {
    let provider: SocialProviderKind
    let idToken: String
    /// The raw nonce of this attempt.
    let nonce: String
    /// Apple only: single-use, valid five minutes, sent at once.
    var authorizationCode: String?
    /// Apple only, and only on the first authorization.
    var firstName: String?
    var lastName: String?
    /// What the provider said about the person, never sent: it prefills the request-access form after
    /// `invite_required`.
    var prefill = SocialPrefill()
}

/// The email and name a provider gave (Google's `profile`, Apple's `email` and `fullName`).
struct SocialPrefill: Equatable, Sendable {
    var email: String?
    var firstName: String?
    var lastName: String?
}

/// `profile` of a `profile_required` answer: the finish step's prefill and its token.
struct SocialProfile: Equatable, Sendable {
    /// Single-use, valid 15 minutes, kept in memory only.
    let signupToken: String
    let expiresAt: Date
    /// Shown read-only ("Signed in as …"); with Apple, possibly a private relay address.
    let email: String
    let username: String
    let firstName: String?
    let lastName: String?
    let referralCode: String?
}

/// What `POST /auth/social` gave the member.
enum SocialSignInAnswer: Equatable, Sendable {
    /// `signed_in`: an account was linked, or is now linked to this provider.
    case session(token: String, user: User)
    /// `profile_required`: a new member, the finish step comes next.
    case profileRequired(SocialProfile)
    /// `403 banned` with a session (`error.token`), as for an email sign-in.
    case suspended(token: String)
}

/// What the finish step sends (`POST /auth/social/complete`). Text is already trimmed.
struct SocialSignUpForm: Equatable, Sendable {
    let signupToken: String
    let firstName: String
    let lastName: String
    let username: String
    /// Sent as typed; nil when empty.
    let referralCode: String?
}

/// Which provider buttons the sign-in and sign-up screens show (slice G, Showing the buttons).
struct SocialAvailability: Equatable, Sendable {
    var apple = false
    var google = false

    var isEmpty: Bool { !apple && !google }

    /// - Parameters:
    ///   - features: `features` of `GET /config`.
    ///   - googleConfigured: the build has a Google iOS client ID (`GIDClientID`).
    ///   - allowsGoogleWithoutApple: App Store guideline 4.8 says an iOS build that offers Google also offers
    ///     Apple, so Google shows only with Apple. Debug builds may show Google alone, to test it against a
    ///     server that has no Apple key.
    static func of(_ features: RemoteFeatures, googleConfigured: Bool, allowsGoogleWithoutApple: Bool) -> SocialAvailability {
        let apple = features.appleSignIn
        let google = features.googleSignIn && googleConfigured && (apple || allowsGoogleWithoutApple)
        return SocialAvailability(apple: apple, google: google)
    }
}
