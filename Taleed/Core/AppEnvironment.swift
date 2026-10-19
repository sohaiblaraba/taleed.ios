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
    /// The app's Apple ID in App Store Connect (`TALEED_APP_STORE_ID`), nil until the record exists.
    let appStoreID: String?

    /// The App Store page that the update screen opens: `https://apps.apple.com/app/id<ID>`.
    var appStoreURL: URL? {
        guard let appStoreID, !appStoreID.isEmpty, appStoreID.allSatisfy(\.isASCIIDigit) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    }

    static func current(bundle: Bundle = .main) -> AppEnvironment {
        let info = bundle.infoDictionary ?? [:]
        guard let base = info["TaleedAPIBaseURL"] as? String, let apiBaseURL = URL(string: base) else {
            preconditionFailure("TaleedAPIBaseURL is missing from Info.plist")
        }
        var appVersion = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        #if DEBUG
        // `-TaleedDebugAppVersion 0.9.0`: check the update screen against the local server.
        if let version = UserDefaults.standard.string(forKey: "TaleedDebugAppVersion") { appVersion = version }
        #endif
        return AppEnvironment(
            apiBaseURL: apiBaseURL,
            appVersion: appVersion,
            buildNumber: info["CFBundleVersion"] as? String ?? "0",
            appStoreID: (info["TaleedAppStoreID"] as? String)?.trimmingCharacters(in: .whitespaces)
        )
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
