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

    @ObservationIgnored private let api: TaleedApi
    @ObservationIgnored private let session: SessionManager
    @ObservationIgnored private let environment: AppEnvironment

    init(api: TaleedApi, session: SessionManager, environment: AppEnvironment) {
        self.api = api
        self.session = session
        self.environment = environment
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

    /// The app came back to the foreground: refresh the member (badges later).
    func didReturnToForeground() async {
        guard phase == .ready else { return }
        await session.refresh()
    }
}
