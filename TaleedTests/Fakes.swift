import Foundation
@testable import Taleed

/// A `TaleedApi` that answers from canned results.
@MainActor
final class FakeTaleedApi: TaleedApi {
    var configResult: Result<RemoteConfig, ApiError> = .success(.fixture())
    var meResult: Result<User, ApiError> = .success(.fixture())
    var catalogResult: Result<Catalog, ApiError> = .success(.fixture())
    var openConversationResult: Result<String, ApiError> = .success("conversation-1")
    private(set) var catalogCalls = 0
    private(set) var openedConversations: [(listingId: String, buyerId: String?)] = []
    var signInResult: Result<(token: String, user: User), ApiError> = .success(("new-token", .fixture()))
    private(set) var meCalls = 0
    private(set) var signedOutTokens: [String] = []
    var onUnauthorized: ((String) -> Void)?
    var onBanned: ((String) -> Void)?

    /// Set to make `me()` behave like the generated client wrapper on a 401 or a 403 `banned`.
    var sentToken: () -> String? = { nil }
    /// Runs once while the next `me()` waits for its answer, after the request left with its token: a
    /// sign-out or a sign-in that happens during the call.
    var whileMeIsInFlight: (() async -> Void)?

    func config() async throws(ApiError) -> RemoteConfig { try configResult.get() }

    func catalog() async throws(ApiError) -> Catalog {
        catalogCalls += 1
        return try catalogResult.get()
    }

    func me(automatic: Bool) async throws(ApiError) -> User {
        meCalls += 1
        let token = sentToken()
        if let inFlight = whileMeIsInFlight {
            whileMeIsInFlight = nil
            await inFlight()
        }
        if let token {
            switch meResult {
            case .failure(.unauthorized): onUnauthorized?(token)
            case .failure(.banned): onBanned?(token)
            default: break
            }
        }
        return try meResult.get()
    }

    func signIn(email: String, password: String) async throws(ApiError) -> (token: String, user: User) {
        try signInResult.get()
    }

    func signOut(token: String) async throws(ApiError) {
        signedOutTokens.append(token)
    }

    func openConversation(listingId: String, buyerId: String?) async throws(ApiError) -> String {
        openedConversations.append((listingId, buyerId))
        return try openConversationResult.get()
    }
}

/// A `TokenStore` in memory.
final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func load() -> String? { lock.withLock { token } }
    func save(_ token: String) { lock.withLock { self.token = token } }
    func delete() { lock.withLock { token = nil } }
}

extension RemoteConfig {
    static func fixture(minimumVersion: String = "1.0.0") -> RemoteConfig {
        RemoteConfig(
            minimumVersion: minimumVersion,
            support: SupportContacts(email: "contact@taleed.app", phone: "+213540693236", whatsappURL: nil)
        )
    }
}

extension Catalog {
    static func fixture(categories: [CatalogCategory] = [CatalogCategory(id: "c1", slug: "femmes", name: "Femmes")]) -> Catalog {
        Catalog(
            categories: categories,
            conditions: [CatalogCondition(value: "VERY_GOOD", label: "Très bon état", shortLabel: "Très bon")],
            sorts: [CatalogOption(value: "newest", label: "Nouveautés")],
            wilayas: [CatalogWilaya(id: 16, name: "Alger")],
            reportReasons: [],
            disputeReasons: [],
            payoutMethods: []
        )
    }
}

extension User {
    static func fixture(username: String = "amina") -> User {
        User(
            id: "u1",
            username: username,
            displayName: "@\(username)",
            avatarURL: nil,
            isVerified: false,
            isOfficial: false
        )
    }
}

extension AppEnvironment {
    static func fixture(appVersion: String = "1.0.0") -> AppEnvironment {
        AppEnvironment(
            apiBaseURL: URL(string: "http://localhost:3000/api/v1")!,
            appVersion: appVersion,
            buildNumber: "1",
            appStoreID: nil
        )
    }
}

/// An `AuthApi` that answers from canned results and records what it was sent.
@MainActor
final class FakeAuthApi: AuthApi {
    var signUpResult: Result<(token: String, user: User), ApiError> = .success(("signup-token", .fixture(username: "nouveau")))
    var resetResult: Result<Void, ApiError> = .success(())
    var accessResult: Result<Void, ApiError> = .success(())
    private(set) var signUps: [SignUpForm] = []
    private(set) var resetEmails: [String] = []
    private(set) var accessRequests: [AccessRequestForm] = []

    func signUp(_ form: SignUpForm) async throws(ApiError) -> (token: String, user: User) {
        signUps.append(form)
        return try signUpResult.get()
    }

    func requestPasswordReset(email: String) async throws(ApiError) {
        resetEmails.append(email)
        try resetResult.get()
    }

    func requestAccess(_ form: AccessRequestForm) async throws(ApiError) {
        accessRequests.append(form)
        try accessResult.get()
    }
}
