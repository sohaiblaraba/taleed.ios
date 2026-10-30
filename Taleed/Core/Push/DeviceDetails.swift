import Foundation
import TaleedAPI
import UIKit

/// What `POST /devices` says about this installation besides its token (slice J, decision 1): kept with the
/// push device for debugging. Never the member's name, email address or phone number.
struct DeviceDetails: Equatable, Sendable {
    /// `CFBundleShortVersionString`, such as `20261002`.
    var appVersion: String
    /// `CFBundleVersion`, such as `20261002`.
    var appBuild: String
    /// `UIDevice.systemVersion`, such as `18.1`.
    var osVersion: String
    /// Always `Apple` on iOS.
    var deviceManufacturer = "Apple"
    /// `utsname.machine`, such as `iPhone16,2`.
    var deviceModel: String

    @MainActor
    static func current(environment: AppEnvironment) -> DeviceDetails {
        DeviceDetails(appVersion: environment.appVersion, appBuild: environment.buildNumber,
                      osVersion: UIDevice.current.systemVersion, deviceModel: machine())
    }

    /// `utsname.machine`: the hardware model, such as `iPhone16,2`. The simulator answers its Mac's `arm64`,
    /// so there the model it simulates (`SIMULATOR_MODEL_IDENTIFIER`) is sent instead.
    static func machine() -> String {
        #if targetEnvironment(simulator)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        #endif
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(bytes: buffer.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
        }
    }
}

extension DeviceRegistration {
    /// The body of `POST /devices`: the token, `ios`, the app's language and the five device details,
    /// each trimmed and cut to the API's limit (`400 invalid_request` above it); an empty one is not sent.
    init(token: String, language: AppLanguage, details: DeviceDetails) {
        self.init(
            token: token,
            platform: .ios,
            locale: ModelLocale(rawValue: language.rawValue),
            appVersion: Self.field(details.appVersion, rule: Self.appVersionRule),
            appBuild: Self.field(details.appBuild, rule: Self.appBuildRule),
            osVersion: Self.field(details.osVersion, rule: Self.osVersionRule),
            deviceManufacturer: Self.field(details.deviceManufacturer, rule: Self.deviceManufacturerRule),
            deviceModel: Self.field(details.deviceModel, rule: Self.deviceModelRule)
        )
    }

    private static func field(_ value: String, rule: StringRule) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let max = rule.maxLength else { return trimmed }
        return String(trimmed.prefix(max))
    }
}
