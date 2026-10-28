import AuthenticationServices
import Foundation
import GoogleSignIn
import UIKit

/// What a provider's sheet ended with.
enum SocialProviderResult: Equatable, Sendable {
    case credential(SocialCredential)
    /// The member closed the sheet: stay on the screen without a message.
    case canceled
    /// The SDK failed (no network, a configuration error): "Sign-in did not go through".
    case failed
}

/// The Google SDK, behind a protocol so that the sign-in flow can be tested without it.
@MainActor
protocol GoogleSignInClient: AnyObject {
    /// The build has an iOS client ID (`GIDClientID` in Info.plist).
    var isConfigured: Bool { get }
    /// Shows Google's sign-in page with this attempt's raw nonce.
    func signIn(nonce: String) async -> SocialProviderResult
    /// Forgets the Google account, so the next sign-in shows the account chooser.
    func signOut()
    /// The redirect back from Google's page. True when it was Google's.
    func handle(_ url: URL) -> Bool
}

/// GoogleSignIn-iOS (slice G, Google on iOS). It reads `GIDClientID` from Info.plist; no `GIDServerClientID`,
/// the app needs no server auth code.
@MainActor
final class GoogleSignInSDKClient: GoogleSignInClient {
    var isConfigured: Bool {
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        return !clientID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func signIn(nonce: String) async -> SocialProviderResult {
        guard isConfigured, let presenter = InAppBrowser.topViewController() else { return .failed }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil,
                                                                   additionalScopes: nil, nonce: nonce)
            guard let idToken = result.user.idToken?.tokenString else { return .failed }
            let profile = result.user.profile
            let prefill = SocialPrefill(email: profile?.email, firstName: profile?.givenName, lastName: profile?.familyName)
            return .credential(SocialCredential(provider: .google, idToken: idToken, nonce: nonce, prefill: prefill))
        } catch {
            return Self.isCancel(error) ? .canceled : .failed
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// `GIDSignInError.canceled`: the member closed Google's page.
    nonisolated static func isCancel(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue
    }
}

/// Sign in with Apple (slice G, Apple on iOS). `SignInWithAppleButton` runs the sheet; this reads what it
/// gave.
enum AppleSignIn {
    /// The request of one attempt: the name and email scopes, and the SHA-256 of the raw nonce.
    static func configure(_ request: ASAuthorizationAppleIDRequest, nonce: String) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = SocialNonce.sha256Hex(nonce)
    }

    /// The credential for `POST /auth/social`: the identity token and the authorization code as UTF-8, and
    /// the name Apple gives on the first authorization only.
    static func result(of completion: Result<ASAuthorization, any Error>, nonce: String) -> SocialProviderResult {
        switch completion {
        case let .success(authorization):
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = apple.identityToken
            else { return .failed }
            return .credential(credential(idToken: tokenData, authorizationCode: apple.authorizationCode,
                                          fullName: apple.fullName, email: apple.email, nonce: nonce))
        case let .failure(error):
            return isCancel(error) ? .canceled : .failed
        }
    }

    /// `email` comes, like the name, only on the first authorization.
    static func credential(idToken: Data, authorizationCode: Data?, fullName: PersonNameComponents?,
                           email: String? = nil, nonce: String) -> SocialCredential {
        let firstName = nonEmpty(fullName?.givenName)
        let lastName = nonEmpty(fullName?.familyName)
        return SocialCredential(provider: .apple, idToken: String(bytes: idToken, encoding: .utf8) ?? "", nonce: nonce,
                                authorizationCode: authorizationCode.flatMap { String(bytes: $0, encoding: .utf8) },
                                firstName: firstName, lastName: lastName,
                                prefill: SocialPrefill(email: nonEmpty(email), firstName: firstName, lastName: lastName))
    }

    /// `ASAuthorizationError.canceled`: the member closed Apple's sheet.
    static func isCancel(_ error: any Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
