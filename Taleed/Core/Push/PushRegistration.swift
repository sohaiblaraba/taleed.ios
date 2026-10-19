import SwiftUI
import TaleedAPI
import UserNotifications

/// `POST /devices` (slice C, Registering the device).
@MainActor
protocol DevicesApi: AnyObject {
    /// Registers this installation for pushes in `language`. Idempotent.
    func registerDevice(token: String, language: AppLanguage) async throws(ApiError)
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
@MainActor
final class PushRegistration {
    private let api: DevicesApi
    private let permission: NotificationPermission
    private let tokenSource: PushTokenSource?
    private let isEnabled: () -> Bool
    private let language: () -> AppLanguage
    /// Registered in this session: the next messages do not register again.
    private var isRegistered = false
    private var isWorking = false

    init(api: DevicesApi, permission: NotificationPermission, tokenSource: PushTokenSource?,
         isEnabled: @escaping () -> Bool, language: @escaping () -> AppLanguage) {
        self.api = api
        self.permission = permission
        self.tokenSource = tokenSource
        self.isEnabled = isEnabled
        self.language = language
    }

    /// The member sent a message or made an offer. Asks for the permission the first time; a member
    /// who said no is never asked again here (the system settings can change it). Best effort: a failed
    /// registration is tried again after the next message.
    func memberReachedOut() async {
        guard isEnabled(), let tokenSource, !isRegistered, !isWorking else { return }
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
