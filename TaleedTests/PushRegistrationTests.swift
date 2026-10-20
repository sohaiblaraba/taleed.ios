import Foundation
@testable import Taleed
import Testing

@MainActor
private final class FakeDevicesApi: DevicesApi {
    private(set) var registered: [(token: String, language: AppLanguage)] = []
    var failure: Taleed.ApiError?

    private(set) var unregistered = 0

    func registerDevice(token: String, language: AppLanguage) async throws(Taleed.ApiError) {
        if let failure { throw failure }
        registered.append((token, language))
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
    func registrationToken() async -> String? { "fcm-token" }
}

@MainActor
struct PushRegistrationTests {
    private let api = FakeDevicesApi()
    private let permission = FakePermission()

    private let defaults = UserDefaults(suiteName: "PushRegistrationTests.\(UUID().uuidString)")!

    private func registration(enabled: Bool = true, signedIn: Bool = true, tokens: PushTokenSource? = FakeTokenSource(),
                              language: @escaping () -> AppLanguage = { .ar }) -> PushRegistration {
        PushRegistration(api: api, permission: permission, tokenSource: tokens, isEnabled: { enabled }, isSignedIn: { signedIn },
                         language: language, defaults: defaults)
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
}
