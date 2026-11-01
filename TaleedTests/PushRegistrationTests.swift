import Foundation
@testable import Taleed
import Testing

@MainActor
private final class FakeDevicesApi: DevicesApi {
    struct Registration {
        let token: String
        let language: AppLanguage
        let details: DeviceDetails
    }

    private(set) var registered: [Registration] = []
    var failure: Taleed.ApiError?

    private(set) var unregistered = 0

    func registerDevice(token: String, language: AppLanguage, details: DeviceDetails) async throws(Taleed.ApiError) {
        if let failure { throw failure }
        registered.append(Registration(token: token, language: language, details: details))
    }

    func unregisterDevice() async throws(Taleed.ApiError) {
        if let failure { throw failure }
        unregistered += 1
    }
}

@MainActor
private final class FakePermission: NotificationPermission {
    var granted: Bool?
    var answer = true
    private(set) var requests = 0

    func isGranted() async -> Bool? { granted }

    func request() async -> Bool {
        requests += 1
        granted = answer
        return answer
    }
}

@MainActor
private final class FakeTokenSource: PushTokenSource {
    var token = "fcm-token"
    func registrationToken() async -> String? { token }
}

private let sampleDetails = DeviceDetails(appVersion: "20261002", appBuild: "20261002", osVersion: "26.0",
                                          deviceModel: "iPhone18,2")

@MainActor
struct PushRegistrationTests {
    private let api = FakeDevicesApi()
    private let permission = FakePermission()

    private let defaults = UserDefaults(suiteName: "PushRegistrationTests.\(UUID().uuidString)")!

    private func registration(enabled: Bool = true, signedIn: Bool = true, tokens: PushTokenSource? = FakeTokenSource(),
                              language: @escaping () -> AppLanguage = { .ar }) -> PushRegistration {
        PushRegistration(api: api, permission: permission, tokenSource: tokens, isEnabled: { enabled }, isSignedIn: { signedIn },
                         language: language, details: { sampleDetails }, defaults: defaults)
    }

    /// The Settings switch shows only with `features.push` and a token source.
    @Test func theSwitchNeedsPushAndAToken() {
        #expect(registration().canBeSwitched)
        #expect(!registration(enabled: false).canBeSwitched)
        #expect(!registration(tokens: nil).canBeSwitched)
    }

    /// Never registered, or the permission never given: the switch is off, whatever the stored choice.
    @Test func theSwitchShowsTheRealState() async {
        let push = registration()
        #expect(!push.isSwitchedOn)
        permission.granted = false
        await push.refresh()
        #expect(!push.isSwitchedOn)
        #expect(push.isPermissionDenied)
        #expect(api.registered.isEmpty)
        permission.granted = true
        await push.refresh()
        #expect(push.isSwitchedOn)
        #expect(!push.isPermissionDenied)
        #expect(api.registered.count == 1)
    }

    @Test func switchingOffUnregistersAndStopsLaterRegistrations() async {
        permission.granted = true
        let push = registration()
        await push.sessionDidStart()
        #expect(push.isSwitchedOn)
        #expect(await push.setSwitchedOn(false) == .done)
        #expect(api.unregistered == 1)
        #expect(!push.isSwitchedOn)
        await push.memberReachedOut()
        await push.languageDidChange()
        await push.sessionDidStart()
        #expect(api.registered.count == 1)
        // Kept on the device.
        #expect(!registration().isWanted)
    }

    @Test func switchingOnAsksThenRegisters() async {
        let push = registration()
        _ = await push.setSwitchedOn(false)
        #expect(await push.setSwitchedOn(true) == .done)
        #expect(permission.requests == 1)
        #expect(api.registered.map(\.token) == ["fcm-token"])
        #expect(push.isSwitchedOn)
    }

    @Test func aRefusedPermissionLeavesTheSwitchOffAndPointsToTheSystemSettings() async {
        let push = registration()
        _ = await push.setSwitchedOn(false)
        permission.answer = false
        #expect(await push.setSwitchedOn(true) == .permissionDenied)
        #expect(!push.isSwitchedOn)
        #expect(push.isPermissionDenied)
        // Refused before: not asked again, the system settings decide.
        #expect(await push.setSwitchedOn(true) == .permissionDenied)
        #expect(permission.requests == 1)
    }

    @Test func aFailedRegistrationLeavesTheSwitchAsItWas() async {
        permission.granted = true
        let push = registration()
        _ = await push.setSwitchedOn(false)
        api.failure = .network
        #expect(await push.setSwitchedOn(true) == .failed)
        #expect(!push.isSwitchedOn)
        #expect(!push.isWanted)
    }

    /// Each sign-in registers once the permission is granted, without asking for it.
    @Test func aSignInRegistersOnlyWithTheGrantedPermission() async {
        let push = registration()
        await push.sessionDidStart()
        #expect(permission.requests == 0)
        #expect(api.registered.isEmpty)
        permission.granted = true
        await push.sessionDidStart()
        #expect(api.registered.count == 1)
        // A new session registers again (the phone may have changed hands).
        push.sessionDidEnd()
        await push.sessionDidStart()
        #expect(api.registered.count == 2)
    }

    /// A new session that has not sent a message yet: the language switch still registers again.
    @Test func aLanguageSwitchRegistersAgainWithoutAMessage() async {
        permission.granted = true
        var language = AppLanguage.fr
        let push = registration(language: { language })
        await push.sessionDidStart()
        language = .ar
        await push.languageDidChange()
        #expect(api.registered.map(\.language) == [.fr, .ar])
    }

    @Test func nothingIsRegisteredSignedOut() async {
        permission.granted = true
        let push = registration(signedIn: false)
        await push.sessionDidStart()
        await push.languageDidChange()
        await push.memberReachedOut()
        #expect(api.registered.isEmpty)
    }

    @Test func aLanguageSwitchRegistersAgain() async {
        let push = registration()
        await push.memberReachedOut()
        await push.languageDidChange()
        #expect(api.registered.count == 2)
    }

    @Test func asksAfterTheFirstMessageThenRegistersOnce() async {
        let push = registration()
        await push.memberReachedOut()
        #expect(permission.requests == 1)
        #expect(api.registered.map(\.token) == ["fcm-token"])
        #expect(api.registered.first?.language == .ar)
        await push.memberReachedOut()
        #expect(permission.requests == 1)
        #expect(api.registered.count == 1)
    }

    /// `features.push` is `false` (a local backend): nothing is asked or registered.
    @Test func nothingWhilePushIsOff() async {
        permission.granted = true
        let push = registration(enabled: false)
        await push.memberReachedOut()
        await push.sessionDidStart()
        await push.languageDidChange()
        #expect(permission.requests == 0)
        #expect(api.registered.isEmpty)
    }

    /// A build without a token source (no Firebase yet) never asks for a permission it cannot use.
    @Test func nothingWithoutATokenSource() async {
        await registration(tokens: nil).memberReachedOut()
        #expect(permission.requests == 0)
    }

    @Test func aRefusalIsNotAskedAgain() async {
        permission.answer = false
        let push = registration()
        await push.memberReachedOut()
        await push.memberReachedOut()
        #expect(permission.requests == 1)
        #expect(api.registered.isEmpty)
    }

    @Test func aFailedRegistrationIsTriedAfterTheNextMessage() async {
        api.failure = .network
        let push = registration()
        await push.memberReachedOut()
        api.failure = nil
        await push.memberReachedOut()
        #expect(api.registered.count == 1)
        #expect(permission.requests == 1)
    }

    /// Every registration sends the five device details (slice J).
    @Test func eachRegistrationSendsTheDeviceDetails() async {
        permission.granted = true
        let push = registration()
        await push.sessionDidStart()
        await push.languageDidChange()
        #expect(api.registered.map(\.details) == [sampleDetails, sampleDetails])
    }

    /// Firebase rotated the token: it registers again; the same token again is not sent twice.
    @Test func aNewTokenRegistersAgain() async {
        permission.granted = true
        let tokens = FakeTokenSource()
        let push = registration(tokens: tokens)
        await push.sessionDidStart()
        await push.tokenDidChange("fcm-token")
        #expect(api.registered.count == 1)
        tokens.token = "fcm-token-2"
        await push.tokenDidChange("fcm-token-2")
        #expect(api.registered.map(\.token) == ["fcm-token", "fcm-token-2"])
    }

    /// A new token while signed out, or with the permission not given, waits for the next session.
    @Test func aNewTokenSignedOutRegistersNothing() async {
        permission.granted = true
        await registration(signedIn: false).tokenDidChange("fcm-token-2")
        permission.granted = nil
        await registration().tokenDidChange("fcm-token-3")
        #expect(api.registered.isEmpty)
        #expect(permission.requests == 0)
    }

    // MARK: The "Enable notifications" screen (plan/push-prompt.md)

    /// Signed in, `features.push`, a token source, the switch never turned off, the permission never decided and
    /// the screen never shown: it shows.
    @Test func thePromptShowsOnceThePermissionWasNeverDecided() async {
        #expect(await registration().shouldShowPrompt())
    }

    @Test func thePromptNeedsPushATokenAndASession() async {
        #expect(await !registration(enabled: false).shouldShowPrompt())
        #expect(await !registration(tokens: nil).shouldShowPrompt())
        #expect(await !registration(signedIn: false).shouldShowPrompt())
    }

    /// The system permission was already given or refused (the first message asked, say): no screen.
    @Test func thePromptNeedsAnUndecidedPermission() async {
        permission.granted = true
        #expect(await !registration().shouldShowPrompt())
        permission.granted = false
        #expect(await !registration().shouldShowPrompt())
    }

    /// The member turned the Settings switch off on this installation: never the screen.
    @Test func thePromptRespectsTheSettingsSwitch() async {
        permission.granted = true
        _ = await registration().setSwitchedOn(false)
        permission.granted = nil
        #expect(await !registration().shouldShowPrompt())
    }

    /// "Not now" closes without asking, and the screen never shows again on this installation, after a sign-out
    /// and a new sign-in too.
    @Test func notNowClosesAndNeverShowsAgain() async {
        let push = registration()
        push.isPromptPresented = true
        push.promptDidDecline()
        #expect(!push.isPromptPresented)
        #expect(permission.requests == 0)
        #expect(api.registered.isEmpty)
        #expect(await !push.shouldShowPrompt())
        push.sessionDidEnd()
        await push.sessionDidStart()
        #expect(await !push.shouldShowPrompt())
        #expect(await !registration().shouldShowPrompt())
    }

    /// The screen showed (the app may stop before an answer): it never shows again.
    @Test func aShownPromptNeverShowsAgain() async {
        registration().promptDidAppear()
        #expect(await !registration().shouldShowPrompt())
    }

    /// "Enable", then Allow: the system dialog once, `POST /devices`, then the screen closes.
    @Test func enableAsksRegistersThenCloses() async {
        let push = registration()
        push.isPromptPresented = true
        await push.promptDidEnable()
        #expect(permission.requests == 1)
        #expect(api.registered.map(\.token) == ["fcm-token"])
        #expect(api.registered.first?.details == sampleDetails)
        #expect(push.isRegistered)
        #expect(!push.isPromptPresented)
        #expect(await !registration().shouldShowPrompt())
    }

    /// "Enable", then Don't Allow: the screen closes, nothing is registered, and the first message does not ask
    /// again.
    @Test func enableRefusedClosesSilently() async {
        permission.answer = false
        let push = registration()
        push.isPromptPresented = true
        await push.promptDidEnable()
        #expect(permission.requests == 1)
        #expect(api.registered.isEmpty)
        #expect(!push.isPromptPresented)
        #expect(push.isPermissionDenied)
        await push.memberReachedOut()
        #expect(permission.requests == 1)
        #expect(await !registration().shouldShowPrompt())
    }

    /// After "Not now" the first message or offer still asks, as before.
    @Test func afterNotNowTheFirstMessageStillAsks() async {
        let push = registration()
        push.promptDidDecline()
        await push.memberReachedOut()
        #expect(permission.requests == 1)
        #expect(api.registered.count == 1)
    }

    #if DEBUG
    /// The developer menu's "Reset push prompt".
    @Test func theResetShowsThePromptAgain() async {
        let push = registration()
        push.promptDidDecline()
        push.resetPrompt()
        #expect(await push.shouldShowPrompt())
    }
    #endif
}
