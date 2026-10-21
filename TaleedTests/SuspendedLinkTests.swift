import Foundation
@testable import Taleed
import Testing

/// While the account is suspended, links and pushes neither open nor show over the suspended screen: the
/// latest one waits for the suspension to lift, and is dropped when the session ends.
@MainActor
struct SuspendedLinkTests {
    /// A suspended account: a link or a push must not open over the suspended screen (a website page in
    /// the in-app browser on top of it). The latest one waits until the suspension lifts.
    @Test func linksWaitWhileTheAccountIsSuspended() {
        var isSuspended = true
        var opened: [URL] = []
        let router = AppRouter()
        router.isSuspended = { isSuspended }
        router.browser = { opened.append($0) }
        router.launchWillShowItsScreen()

        router.open(url: URL(string: "https://help.example.com/guide")!)
        router.open(url: URL(string: "https://taleed.app/listings/l1")!)
        #expect(opened.isEmpty)
        #expect(router.path(.home).isEmpty)

        isSuspended = false
        router.suspensionDidLift()
        #expect(opened.isEmpty)
        #expect(router.selectedTab == .home)
        #expect(router.path(.home) == [.listing(id: "l1")])
        // Once only.
        router.popToRoot(.home)
        router.suspensionDidLift()
        #expect(router.path(.home).isEmpty)
    }

    @Test func aLinkHeldWhileSuspendedIsDroppedWhenTheSessionEnds() {
        var isSuspended = true
        var opened: [URL] = []
        let router = AppRouter()
        router.isSuspended = { isSuspended }
        router.browser = { opened.append($0) }
        router.launchWillShowItsScreen()
        router.open(url: URL(string: "https://help.example.com/guide")!)

        // Signed out from the suspended screen.
        isSuspended = false
        router.sessionDidEnd()
        router.suspensionDidLift()
        #expect(opened.isEmpty)
    }

    /// Since links from the launch open before the screen shows, a suspended account must hold them: a
    /// website link would otherwise open the in-app browser over the suspended screen.
    @Test func aLinkFromTheLaunchWaitsWhileTheAccountIsSuspended() async {
        let api = FakeTaleedApi()
        api.meResult = .failure(.banned)
        let apiSession = ApiSession(environment: .fixture(), language: .fr, configuration: .init())
        let session = SessionManager(api: api, apiSession: apiSession, tokenStore: InMemoryTokenStore(token: "t"))
        api.sentToken = { [apiSession] in apiSession.token }
        let launch = LaunchViewModel(api: api, session: session, environment: .fixture())
        let router = AppRouter()
        var opened: [URL] = []
        router.browser = { opened.append($0) }
        router.isSignedIn = { session.isSignedIn || session.hasSuspendedSession }
        router.isSuspended = { session.state == .suspended }
        session.onSuspensionLifted = { router.suspensionDidLift() }
        launch.willShowScreen = { router.launchWillShowItsScreen() }
        router.open(url: URL(string: "https://help.example.com/guide")!)

        await launch.start()

        #expect(launch.route == .suspended(RemoteConfig.fixture().support))
        #expect(opened.isEmpty)

        // A push while suspended waits too.
        router.open(url: URL(string: "taleed://wallet")!)
        #expect(router.path(.profile).isEmpty)

        // The suspension is lifted: the shell shows with the latest link.
        api.meResult = .success(.fixture())
        await launch.didReturnToForeground()
        #expect(launch.route == .main)
        #expect(opened.isEmpty)
        #expect(router.selectedTab == .profile)
        #expect(router.path(.profile) == [.wallet])
    }
}
