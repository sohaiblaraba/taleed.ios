import Foundation
@testable import Taleed
import Testing

/// The bell and Messages badges keep their last known count while offline, and take the server's
/// again (`GET /me`) once the device is online.
@MainActor
struct BadgeRefreshTests {
    private let api = FakeTaleedApi()
    private let apiSession = ApiSession(environment: .fixture(), language: .fr, configuration: .init())

    private func makeLaunch() -> (LaunchViewModel, SessionManager) {
        let session = SessionManager(api: api, apiSession: apiSession, tokenStore: InMemoryTokenStore(token: "t"))
        api.sentToken = { [apiSession] in apiSession.token }
        return (LaunchViewModel(api: api, session: session, environment: .fixture()), session)
    }

    @Test func comingBackOnlineRefreshesTheBadges() async {
        let (launch, session) = makeLaunch()
        await launch.start()
        var user = User.fixture()
        user.unreadNotifications = 11
        user.unreadMessages = 3
        api.meResult = .success(user)

        await launch.didComeBackOnline()

        #expect(api.meCalls == 2)
        #expect(session.user?.unreadNotifications == 11)
        #expect(session.user?.unreadMessages == 3)
    }

    @Test func anOfflineRefreshKeepsTheLastKnownBadges() async {
        let (launch, session) = makeLaunch()
        await launch.start()
        session.updateUnreadCounts(messages: 2, notifications: 7)
        api.meResult = .failure(.network)

        await launch.didReturnToForeground()

        #expect(session.user?.unreadNotifications == 7)
        #expect(session.user?.unreadMessages == 2)
    }

    @Test func comingBackOnlineBeforeTheLaunchEndsAsksNothing() async {
        let (launch, _) = makeLaunch()
        await launch.didComeBackOnline()
        #expect(api.meCalls == 0)
    }

    @Test func onlyAReturnOnlineCallsBack() {
        let network = NetworkMonitor(startsMonitoring: false)
        var calls = 0
        network.onBackOnline = { calls += 1 }
        network.pathDidChange(isOnline: true)
        #expect(calls == 0)
        network.pathDidChange(isOnline: false)
        #expect(!network.isOnline)
        network.pathDidChange(isOnline: false)
        #expect(calls == 0)
        network.pathDidChange(isOnline: true)
        #expect(network.isOnline)
        #expect(calls == 1)
    }
}
