import Foundation
import Observation

/// Runs the launch flow: `GET /config`, the minimum version check, then `GET /me` when a token
/// is stored. Decides which top-level screen the app shows.
@MainActor
@Observable
final class LaunchViewModel {
    enum Route: Equatable {
        case loading
        /// No answer decided the launch. The screen offers a retry.
        case failed(ApiError)
        case updateRequired
        case suspended(SupportContacts)
        case main
    }

    private enum Phase: Equatable {
        case loading
        case failed(ApiError)
        case updateRequired
        case ready
    }

    private var phase: Phase = .loading
    private(set) var config: RemoteConfig?
    /// Debug builds: `-TaleedDebugVisualSearch YES` shows the photo-search button while the server has
    /// it off (screenshots, and the `503 feature_disabled` path). Cleared by that answer.
    private var forcesVisualSearch = false

    @ObservationIgnored private let api: TaleedApi
    @ObservationIgnored private let session: SessionManager
    @ObservationIgnored private let environment: AppEnvironment

    init(api: TaleedApi, session: SessionManager, environment: AppEnvironment) {
        self.api = api
        self.session = session
        self.environment = environment
        #if DEBUG
        forcesVisualSearch = UserDefaults.standard.bool(forKey: "TaleedDebugVisualSearch")
        #endif
    }

    /// Search by photo is offered (`features.visualSearch` of `GET /config`, slice B).
    var isVisualSearchEnabled: Bool {
        forcesVisualSearch || (config?.features.visualSearch ?? false)
    }

    /// The API answered `503 feature_disabled` to a photo search: hide the button at once, then read
    /// `GET /config` again (slice B, Search by photo).
    func visualSearchWasDisabled() async {
        forcesVisualSearch = false
        config?.features.visualSearch = false
        if let fresh = try? await api.config() { config = fresh }
    }

    var route: Route {
        switch phase {
        case .loading: .loading
        case let .failed(error): .failed(error)
        case .updateRequired: .updateRequired
        case .ready:
            if session.state == .suspended, let config {
                .suspended(config.support)
            } else {
                .main
            }
        }
    }

    func start() async {
        phase = .loading
        do {
            let config = try await api.config()
            self.config = config
            if VersionComparator.isVersion(environment.appVersion, below: config.minimumVersion) {
                phase = .updateRequired
                return
            }
            try await session.restore()
            phase = .ready
        } catch {
            phase = .failed(error)
        }
    }

    /// The app language changed (Settings, no restart): read `GET /config` again in the new language, so
    /// its `links` (terms, privacy, buyer protection, guides, website) carry the new language prefix
    /// (API 1.5.11). On failure the current config stays; the launch route does not change.
    func languageDidChange() async {
        guard config != nil, let fresh = try? await api.config() else { return }
        config = fresh
    }

    /// The app came back to the foreground: refresh the member (badges later).
    func didReturnToForeground() async {
        guard phase == .ready else { return }
        await session.refresh()
    }
}
