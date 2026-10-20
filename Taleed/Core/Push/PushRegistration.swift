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
/// This build has none yet: Firebase (the SDK and each environment's `GoogleService-Info.plist`, plan
/// action 3) brings it, with the token refresh. `PushRegistration` already owns the push switch and the
/// registration after sign-in and after a language switch.
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
/// Registers again, without asking, after each sign-in (and at launch with a session) once the permission
/// is granted, and after a language switch, so pushes follow the new language (slice C, Registering the
/// device; screens.md §0.8).
///
/// The switch in Settings (G16) turns pushes off for this installation (`DELETE /devices`) and back on
/// (the permission, then `POST /devices`); the choice is kept on the device. It shows the real state: on
/// only while the member wants pushes, the system allows them and this installation is registered.
@MainActor
@Observable
final class PushRegistration {
    /// What turning the Settings switch on or off did.
    enum SwitchResult: Equatable {
        case done
        /// The system refuses notifications: only the system settings can allow them again.
        case permissionDenied
        /// No token, or the API did not answer: the switch stays as it was.
        case failed
    }

    @ObservationIgnored private let api: DevicesApi
    @ObservationIgnored private let permission: NotificationPermission
    @ObservationIgnored private let tokenSource: PushTokenSource?
    @ObservationIgnored private let isEnabled: () -> Bool
    @ObservationIgnored private let isSignedIn: () -> Bool
    @ObservationIgnored private let language: () -> AppLanguage
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isWorking = false
    /// This installation is registered for the current session.
    private(set) var isRegistered = false
    /// The system permission as last read: `nil` before the member was asked (or before it was read).
    private(set) var isPermissionGranted: Bool?
    /// The member's choice on this device: true unless they turned pushes off in Settings.
    private(set) var isWanted: Bool

    static let switchKey = "push_switched_on"

    init(api: DevicesApi, permission: NotificationPermission, tokenSource: PushTokenSource?,
         isEnabled: @escaping () -> Bool, isSignedIn: @escaping () -> Bool = { true },
         language: @escaping () -> AppLanguage, defaults: UserDefaults = .standard) {
        self.api = api
        self.permission = permission
        self.tokenSource = tokenSource
        self.isEnabled = isEnabled
        self.isSignedIn = isSignedIn
        self.language = language
        self.defaults = defaults
        isWanted = defaults.object(forKey: Self.switchKey) as? Bool ?? true
    }

    /// The Settings switch shows only when the server sends pushes (`features.push`) and the build can
    /// get a token.
    var canBeSwitched: Bool { isEnabled() && tokenSource != nil }

    /// The Settings switch: on only when pushes really reach this installation.
    var isSwitchedOn: Bool { isWanted && isPermissionGranted == true && isRegistered }

    /// The system refuses notifications: the Settings switch points to the system settings.
    var isPermissionDenied: Bool { isPermissionGranted == false }

    /// The Settings switch. Off: `DELETE /devices`. On: the permission (asked when it never was), then
    /// `POST /devices`. Anything but `.done` leaves the switch as it was.
    func setSwitchedOn(_ isOn: Bool) async -> SwitchResult {
        guard canBeSwitched, let tokenSource else { return .failed }
        if isOn {
            switch await readPermission() {
            case nil:
                let granted = await permission.request()
                isPermissionGranted = granted
                guard granted else { return .permissionDenied }
            case true?:
                break
            case false?:
                return .permissionDenied
            }
            guard let token = await tokenSource.registrationToken() else { return .failed }
            do {
                try await api.registerDevice(token: token, language: language())
            } catch {
                return .failed
            }
            isRegistered = true
        } else {
            do {
                try await api.unregisterDevice()
            } catch {
                return .failed
            }
            isRegistered = false
        }
        isWanted = isOn
        defaults.set(isOn, forKey: Self.switchKey)
        return .done
    }

    /// A session started: a sign-in, a sign-up, or launch with a stored session. Registers when the
    /// permission is already granted; never asks for it here (slice C, Registering the device).
    func sessionDidStart() async {
        isRegistered = false
        await registerIfAllowed()
    }

    /// The app's language changed: registers again, so pushes follow it (screens.md §0.8).
    func languageDidChange() async {
        await registerIfAllowed(again: true)
    }

    /// Settings opened, or the app came back to the foreground: reads the permission again (the member
    /// may have changed it in the system settings) and registers when it is now granted.
    func refresh() async {
        await registerIfAllowed()
    }

    /// The member sent a message or made an offer. Asks for the permission the first time; a member
    /// who said no is never asked again here (the system settings can change it). Best effort: a failed
    /// registration is tried again after the next message. Nothing while the Settings switch is off.
    func memberReachedOut() async {
        guard isEnabled(), isWanted, let tokenSource, !isRegistered, !isWorking, isSignedIn() else { return }
        isWorking = true
        defer { isWorking = false }
        switch await readPermission() {
        case nil:
            let granted = await permission.request()
            isPermissionGranted = granted
            guard granted else { return }
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

    /// Registers without asking: only with `features.push`, a session, the member's choice and a granted
    /// permission. `again`: even when already registered (a new language).
    private func registerIfAllowed(again: Bool = false) async {
        guard isEnabled(), let tokenSource, again || !isWorking else { return }
        let granted = await readPermission()
        guard isWanted, isSignedIn(), granted == true, again || !isRegistered else { return }
        isWorking = true
        defer { isWorking = false }
        guard let token = await tokenSource.registrationToken() else { return }
        do {
            try await api.registerDevice(token: token, language: language())
            isRegistered = true
        } catch {}
    }

    private func readPermission() async -> Bool? {
        let granted = await permission.isGranted()
        isPermissionGranted = granted
        return granted
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
