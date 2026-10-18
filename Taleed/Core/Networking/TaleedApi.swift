import Foundation
import TaleedAPI

/// The API calls that the app makes, in app models. View models depend on this protocol;
/// only `GeneratedTaleedApi` touches the generated client.
@MainActor
protocol TaleedApi: AnyObject {
    func config() async throws(ApiError) -> RemoteConfig
    func catalogCategories() async throws(ApiError) -> [CatalogCategory]
    func me() async throws(ApiError) -> User
    func signIn(email: String, password: String) async throws(ApiError) -> (token: String, user: User)
    /// Revokes the session of `token` on the server. The caller deletes the token whatever the answer.
    func signOut(token: String) async throws(ApiError)

    /// Called when the API rejects the token that a request carried (`401 unauthorized`),
    /// with that token. `SessionManager` sets it to sign out globally.
    var onUnauthorized: ((String) -> Void)? { get set }
}

@MainActor
final class GeneratedTaleedApi: TaleedApi {
    private let session: ApiSession
    var onUnauthorized: ((String) -> Void)?

    init(session: ApiSession) {
        self.session = session
    }

    func config() async throws(ApiError) -> RemoteConfig {
        let config = try await call { () async throws(ErrorResponse) in
            try await ReferenceAPI.getConfig(apiConfiguration: session.configuration)
        }
        return RemoteConfig(
            minimumVersion: config.minimumVersion.ios,
            support: SupportContacts(
                email: config.support.email,
                phone: config.support.phone,
                whatsappURL: URL(string: config.support.whatsappUrl)
            )
        )
    }

    func catalogCategories() async throws(ApiError) -> [CatalogCategory] {
        let catalog = try await call { () async throws(ErrorResponse) in
            try await ReferenceAPI.getCatalog(apiConfiguration: session.configuration)
        }
        return catalog.categories.map { CatalogCategory(id: $0.id, name: $0.name) }
    }

    func me() async throws(ApiError) -> User {
        let me = try await call { () async throws(ErrorResponse) in
            try await AccountAPI.getMe(apiConfiguration: session.configuration)
        }
        return User(me)
    }

    func signIn(email: String, password: String) async throws(ApiError) -> (token: String, user: User) {
        let request = SignInRequest(email: email, password: password)
        let auth = try await call { () async throws(ErrorResponse) in
            try await AuthAPI.signIn(signInRequest: request, apiConfiguration: session.configuration)
        }
        return (auth.token, User(auth.user))
    }

    func signOut(token: String) async throws(ApiError) {
        let configuration = session.snapshot()
        configuration.customHeaders["Authorization"] = "Bearer \(token)"
        do {
            try await AuthAPI.signOut(apiConfiguration: configuration)
        } catch {
            throw ApiError.from(error)
        }
    }

    /// Runs a generated call, maps its error, and reports a rejected token.
    private func call<T: Sendable>(
        _ operation: () async throws(ErrorResponse) -> T
    ) async throws(ApiError) -> T {
        let sentToken = session.token
        do {
            return try await operation()
        } catch {
            let apiError = ApiError.from(error)
            if apiError == .unauthorized, let sentToken {
                onUnauthorized?(sentToken)
            }
            throw apiError
        }
    }
}

private extension User {
    init(_ me: Me) {
        self.init(
            id: me.id,
            username: me.username,
            displayName: me.displayName,
            avatarURL: me.avatarUrl.flatMap(URL.init(string:)),
            isVerified: me.isVerified,
            isOfficial: me.isOfficial
        )
    }
}
