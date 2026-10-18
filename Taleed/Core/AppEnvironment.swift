import Foundation

/// What the current build talks to and how it identifies itself.
/// The values come from the build configuration (Config/*.xcconfig) through Info.plist.
struct AppEnvironment: Sendable {
    /// The API base URL, such as `http://localhost:3000/api/v1` in Debug.
    let apiBaseURL: URL
    /// The marketing version (`CFBundleShortVersionString`), sent as `X-App-Version`.
    let appVersion: String
    /// The build number (`CFBundleVersion`).
    let buildNumber: String
    /// Sent as `X-App-Platform`.
    let platform = "ios"
    /// The App Store page that the update screen opens. Placeholder until the app is published.
    let appStoreURL: URL

    static func current(bundle: Bundle = .main) -> AppEnvironment {
        let info = bundle.infoDictionary ?? [:]
        guard let base = info["TaleedAPIBaseURL"] as? String, let apiBaseURL = URL(string: base) else {
            preconditionFailure("TaleedAPIBaseURL is missing from Info.plist")
        }
        return AppEnvironment(
            apiBaseURL: apiBaseURL,
            appVersion: info["CFBundleShortVersionString"] as? String ?? "0.0.0",
            buildNumber: info["CFBundleVersion"] as? String ?? "0",
            appStoreURL: URL(string: "https://apps.apple.com/app/taleed")!
        )
    }
}
