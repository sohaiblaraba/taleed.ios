import SwiftUI
import TaleedAPI
import UserNotifications

/// `POST /devices` (slice C, Registering the device).
@MainActor
protocol DevicesApi: AnyObject {
    /// Registers this installation for pushes in `language`. Idempotent.
    func registerDevice(token: String, language: AppLanguage) async throws(ApiError)
    /// `DELETE /devices`: this installation stops receiving pushes. Idempotent.
    func unregisterDevice() async throws(ApiError)
}

/// The installation's Firebase Cloud Messaging registration token, the one `POST /devices` takes.
///
/// This build has none: Firebase (the SDK and each environment's `GoogleService-Info.plist`, plan
/// action 3) arrives with the push setup of G16 Settings, which also owns the push switch, the
/// registration after sign-in and after a language switch, and the token refresh.
@MainActor
protocol PushTokenSource: AnyObject {
    func registrationToken() async -> String?
}

/// The system's notification permission.
@MainActor
protocol NotificationPermission {
    /// `nil` before the member was asked; then whether pushes may show.
    func isGranted() async -> Bool?
    /// Shows the system prompt: whether the member allowed it.
    func request() async -> Bool
}

struct SystemNotificationPermission: NotificationPermission {
    func isGranted() async -> Bool? {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .notDetermined: return nil
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }
}

/// Asks for the push permission at a moment that explains it, after the member's first message or
/// offer, then registers the device (screens.md §2 G9 Ops, slice C "Push notifications"). Only when
/// `GET /config` says `features.push` (`false` on a local backend) and the build can get a token.
///
/// The switch in Settings (G16) turns pushes off for this installation (`DELETE /devices`) and back on
/// (the permission, then `POST /devices`); the choice is kept on the device. A language switch registers
/// again, so pushes follow the new language.
@MainActor
@Observable
final class PushRegistration {
    @ObservationIgnored private let api: DevicesApi
    @ObservationIgnored private let permission: NotificationPermission
    @ObservationIgnored private let tokenSource: PushTokenSource?
    @ObservationIgnored private let isEnabled: () -> Bool
    @ObservationIgnored private let language: () -> AppLanguage
    @ObservationIgnored private let defaults: UserDefaults
    /// Registered in this session: the next messages do not register again.
    @ObservationIgnored private var isRegistered = false
    @ObservationIgnored private var isWorking = false
    /// The Settings switch: on unless the member turned it off on this device.
    private(set) var isSwitchedOn: Bool

    static let switchKey = "push_switched_on"

    init(api: DevicesApi, permission: NotificationPermission, tokenSource: PushTokenSource?,
         isEnabled: @escaping () -> Bool, language: @escaping () -> AppLanguage, defaults: UserDefaults = .standard) {
        self.api = api
        self.permission = permission
        self.tokenSource = tokenSource
        self.isEnabled = isEnabled
        self.language = language
        self.defaults = defaults
        isSwitchedOn = defaults.object(forKey: Self.switchKey) as? Bool ?? true
    }

    /// The Settings switch shows only when the server sends pushes (`features.push`) and the build can
    /// get a token.
    var canBeSwitched: Bool { isEnabled() && tokenSource != nil }

    /// The Settings switch. Off: `DELETE /devices`. On: the permission (asked when it never was), then
    /// `POST /devices`. Returns false when it could not be done; the switch then goes back.
    func setSwitchedOn(_ isOn: Bool) async -> Bool {
        guard canBeSwitched, let tokenSource else { return false }
        if isOn {
            switch await permission.isGranted() {
            case nil:
                guard await permission.request() else { return false }
            case true?:
                break
            case false?:
                return false
            }
            guard let token = await tokenSource.registrationToken() else { return false }
            do {
                try await api.registerDevice(token: token, language: language())
            } catch {
                return false
            }
            isRegistered = true
        } else {
            do {
                try await api.unregisterDevice()
            } catch {
                return false
            }
            isRegistered = false
        }
        isSwitchedOn = isOn
        defaults.set(isOn, forKey: Self.switchKey)
        return true
    }

    /// The app's language changed: a registered installation registers again, so pushes follow it.
    func languageDidChange() async {
        guard isEnabled(), isSwitchedOn, isRegistered, let tokenSource,
              let token = await tokenSource.registrationToken() else { return }
        try? await api.registerDevice(token: token, language: language())
    }

    /// The member sent a message or made an offer. Asks for the permission the first time; a member
    /// who said no is never asked again here (the system settings can change it). Best effort: a failed
    /// registration is tried again after the next message. Nothing while the Settings switch is off.
    func memberReachedOut() async {
        guard isEnabled(), isSwitchedOn, let tokenSource, !isRegistered, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        switch await permission.isGranted() {
        case nil:
            guard await permission.request() else { return }
        case true?:
            break
        case false?:
            return
        }
        guard let token = await tokenSource.registrationToken() else { return }
        do {
            try await api.registerDevice(token: token, language: language())
            isRegistered = true
        } catch {}
    }

    /// Signed out: pushes stop with the session (slice C); the next member registers again.
    func sessionDidEnd() {
        isRegistered = false
    }
}

extension GeneratedTaleedApi: DevicesApi {
    func registerDevice(token: String, language: AppLanguage) async throws(ApiError) {
        let locale = DeviceRegistration.ModelLocale(rawValue: language.rawValue)
        let registration = DeviceRegistration(token: token, platform: .ios, locale: locale)
        // Idempotent (slice C, Registering the device).
        try await caller.call(.read, automatic: true) {
            try await PushAPI.registerDevice(deviceRegistration: registration, apiConfiguration: $0)
        }
    }

    func unregisterDevice() async throws(ApiError) {
        // Idempotent (slice C, Registering the device).
        try await caller.call(.read) { try await PushAPI.unregisterDevice(apiConfiguration: $0) }
    }
}

private struct PushRegistrationKey: EnvironmentKey {
    static var defaultValue: PushRegistration? { nil }
}

extension EnvironmentValues {
    /// Set once at the root (`AppRootView`).
    var pushRegistration: PushRegistration? {
        get { self[PushRegistrationKey.self] }
        set { self[PushRegistrationKey.self] = newValue }
    }
}
