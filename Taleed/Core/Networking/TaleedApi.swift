import Foundation
import TaleedAPI

// How the app calls the API
//
// View models depend on protocols of app models; only `GeneratedTaleedApi` touches the generated
// client. Each screen group adds its own protocol next to its screens (for example `ListingsApi` in
// `Features/Listing`), implements it in an extension of `GeneratedTaleedApi` with
// `caller.call(.read) { try await ListingsAPI.getListing(id: id, apiConfiguration: $0) }`, maps the
// generated models to app models there, and gets the instance from `AppContainer.api`.
// Pass `.write` for actions that must not repeat on their own (api-guide.md, Retrying).

/// The calls of the app shell: launch, session, catalog, and what the router and the debug menu need.
@MainActor
protocol TaleedApi: AnyObject {
    func config() async throws(ApiError) -> RemoteConfig
    func catalog() async throws(ApiError) -> Catalog
    /// `automatic`: a refresh the member did not ask for (return to the foreground).
    func me(automatic: Bool) async throws(ApiError) -> User
    func signIn(email: String, password: String) async throws(ApiError) -> SignInAnswer
    /// Revokes the session of `token` on the server. The caller deletes the token whatever the answer.
    func signOut(token: String) async throws(ApiError)
    /// `POST /conversations` for a `/listings/{id}/chat` link: the conversation's id. `buyerId` (`?with=`)
    /// only when the seller writes to a member; without it the member writes to the seller.
    func openConversation(listingId: String, buyerId: String?) async throws(ApiError) -> String

    /// Called when the API rejects the token that a request carried (`401 unauthorized`),
    /// with that token. `SessionManager` sets it to sign out globally.
    var onUnauthorized: ((String) -> Void)? { get set }
    /// Called when a request that carried a token answers `403 banned` (the account was suspended
    /// meanwhile), with that token. `SessionManager` sets it to show the suspended screen.
    var onBanned: ((String) -> Void)? { get set }
}

extension TaleedApi {
    func me() async throws(ApiError) -> User { try await me(automatic: false) }
}

/// What `POST /auth/sign-in` gave the member.
enum SignInAnswer: Equatable, Sendable {
    /// A session.
    case session(token: String, user: User)
    /// `403 banned` with a session (`error.token`, contract 1.5.1): the suspended member keeps access to
    /// their orders, the wallet and account deletion. A `banned` without a token throws `.banned`.
    case suspended(token: String)

    /// `.suspended` when the sign-in failed with `403 banned` and a token; nil for any other failure.
    static func suspended(from error: ErrorResponse) -> SignInAnswer? {
        guard case let .error(status, body, _, _) = error,
              let token = ApiError.suspendedSessionToken(status: status, body: body)
        else { return nil }
        return .suspended(token: token)
    }
}

/// `POST /uploads` (api-guide.md, Uploads). Use `PhotoUploadService`, which prepares the photo.
@MainActor
protocol UploadsApi: AnyObject {
    /// Uploads a prepared JPEG file. Allow about a minute.
    func upload(file: URL, purpose: UploadPurpose) async throws(ApiError) -> UploadedPhoto
}

/// The step of `POST /orders/{id}/shipment/simulate` (development and staging servers only).
enum ShipmentSimulationStep: String, CaseIterable, Sendable {
    case transit, arrived, delivered
}

/// Development-only calls, for the debug menu. Never call them from a release build's screens.
@MainActor
protocol DevelopmentApi: AnyObject {
    /// Moves a demo parcel forward. `404` unless the server's carrier is the mock one.
    func simulateShipment(orderId: String, step: ShipmentSimulationStep) async throws(ApiError)
}

@MainActor
final class GeneratedTaleedApi: TaleedApi, UploadsApi, DevelopmentApi {
    let session: ApiSession
    /// Runs every generated call: errors, retries, the rejected token.
    let caller: ApiCaller

    var onUnauthorized: ((String) -> Void)? {
        get { caller.onUnauthorized }
        set { caller.onUnauthorized = newValue }
    }

    var onBanned: ((String) -> Void)? {
        get { caller.onBanned }
        set { caller.onBanned = newValue }
    }

    init(session: ApiSession) {
        self.session = session
        caller = ApiCaller(session: session)
    }

    func config() async throws(ApiError) -> RemoteConfig {
        let config = try await caller.call { try await ReferenceAPI.getConfig(apiConfiguration: $0) }
        return RemoteConfig(config)
    }

    func catalog() async throws(ApiError) -> Catalog {
        Catalog(try await caller.call { try await ReferenceAPI.getCatalog(apiConfiguration: $0) })
    }

    func me(automatic: Bool) async throws(ApiError) -> User {
        User(try await caller.call(.read, automatic: automatic) { try await AccountAPI.getMe(apiConfiguration: $0) })
    }

    func signIn(email: String, password: String) async throws(ApiError) -> SignInAnswer {
        let request = SignInRequest(email: email, password: password)
        // Repeating a sign-in does no harm (api-guide.md, Retrying), but a wrong password must not.
        return try await caller.call(.write) { configuration -> SignInAnswer in
            do {
                let auth = try await AuthAPI.signIn(signInRequest: request, apiConfiguration: configuration)
                return .session(token: auth.token, user: User(auth.user))
            } catch let error as ErrorResponse {
                if let suspended = SignInAnswer.suspended(from: error) { return suspended }
                throw error
            }
        }
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

    func openConversation(listingId: String, buyerId: String?) async throws(ApiError) -> String {
        let request = ConversationOpen(listingId: listingId, buyerId: buyerId)
        // Opening the same conversation again returns it (slice C, Retrying).
        let conversation = try await caller.call(.read) {
            try await ConversationsAPI.openConversation(conversationOpen: request, apiConfiguration: $0)
        }
        return conversation.id
    }

    func upload(file: URL, purpose: UploadPurpose) async throws(ApiError) -> UploadedPhoto {
        let generatedPurpose = TaleedAPI.UploadPurpose(rawValue: purpose.rawValue) ?? .unknownDefaultOpenApi
        // A repeated upload stores a new file; one left unused does no harm (slice E, Retrying).
        let upload = try await caller.call(.read, configuration: session.uploadConfiguration()) {
            try await UploadsAPI.createUpload(purpose: generatedPurpose, file: file, apiConfiguration: $0)
        }
        return UploadedPhoto(key: upload.key, url: URL(string: upload.url), thumbURL: URL(string: upload.thumbUrl))
    }

    func simulateShipment(orderId: String, step: ShipmentSimulationStep) async throws(ApiError) {
        let body = ShipmentSimulation(step: TaleedAPI.ShipmentSimulationStep(rawValue: step.rawValue) ?? .unknownDefaultOpenApi)
        try await caller.call(.write) {
            try await DevelopmentAPI.simulateShipment(id: orderId, shipmentSimulation: body, apiConfiguration: $0)
        }
    }
}

// MARK: - Mapping

extension User {
    init(_ me: Me) {
        self.init(
            id: me.id,
            username: me.username,
            displayName: me.displayName,
            avatarURL: me.avatarUrl.flatMap(URL.init(string:)),
            isVerified: me.isVerified,
            isOfficial: me.isOfficial,
            unreadMessages: me.counts.unreadMessages,
            unreadNotifications: me.counts.unreadNotifications,
            wilayaId: me.wilaya?.id
        )
    }
}

private extension RemoteConfig {
    init(_ config: AppConfig) {
        self.init(
            minimumVersion: config.minimumVersion.ios,
            support: SupportContacts(
                email: config.support.email,
                phone: config.support.phone,
                whatsappURL: URL(string: config.support.whatsappUrl)
            ),
            betaMode: config.betaMode,
            features: RemoteFeatures(visualSearch: config.features.visualSearch, identityAiReview: config.features.identityAiReview,
                                     push: config.features.push, googleSignIn: config.features.googleSignIn,
                                     appleSignIn: config.features.appleSignIn),
            // An unknown method is not offered (api-guide.md, Compatibility).
            paymentMethods: config.paymentMethods.filter { $0 != .unknownDefaultOpenApi }.map(\.rawValue),
            links: WebsiteLinks(
                website: URL(string: config.links.website),
                terms: URL(string: config.links.terms),
                privacy: URL(string: config.links.privacy),
                buyerProtection: URL(string: config.links.buyerProtection),
                guides: URL(string: config.links.guides)
            )
        )
    }
}

extension Catalog {
    init(_ catalog: TaleedAPI.Catalog) {
        self.init(
            categories: catalog.categories.map { node in
                CatalogCategory(id: node.id, slug: node.slug, name: node.name,
                                children: node.children.map { CatalogCategory(id: $0.id, slug: $0.slug, name: $0.name) })
            },
            // Values unknown to this build keep their catalog label: tags show it (decision 6).
            conditions: catalog.conditions.map {
                CatalogCondition(value: $0.value.rawValue, label: $0.label, shortLabel: $0.shortLabel)
            },
            sorts: catalog.sorts.compactMap {
                $0.value == .unknownDefaultOpenApi ? nil : CatalogOption(value: $0.value.rawValue, label: $0.label)
            },
            wilayas: catalog.wilayas.map { CatalogWilaya(id: $0.id, name: $0.name) },
            reportReasons: catalog.reportReasons.compactMap {
                $0.value == .unknownDefaultOpenApi ? nil : CatalogOption(value: $0.value.rawValue, label: $0.label)
            },
            disputeReasons: catalog.disputeReasons.compactMap {
                $0.value == .unknownDefaultOpenApi
                    ? nil : CatalogDisputeReason(value: $0.value.rawValue, label: $0.label, needsEvidence: $0.needsEvidence)
            },
            payoutMethods: catalog.payoutMethods.compactMap {
                $0.value == .unknownDefaultOpenApi ? nil : CatalogOption(value: $0.value.rawValue, label: $0.label)
            }
        )
    }
}
