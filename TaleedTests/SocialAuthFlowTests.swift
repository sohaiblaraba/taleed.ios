import Foundation
@testable import Taleed
import Testing

// Slice G: the auth sheet's finish step and the sign-out of the providers.

@MainActor
struct SocialAuthFlowTests {
    private func makeFlow(entry: AuthEntry = .signIn) -> AuthFlowModel {
        AuthFlowModel(entry: entry, session: makeSession().0, api: FakeAuthApi(), isBetaMode: { false },
                      google: FakeGoogleSignIn())
    }

    @Test func theFinishStepTakesTheInviteLinksCode() {
        let flow = makeFlow(entry: .signUp(referralCode: "7DE5395A"))
        flow.showFinishSignUp(.fixture())
        #expect(flow.step == .finishSignUp)
        #expect(flow.finishSignUp?.referralCode == "7de5395a")
    }

    /// The token lives in memory only: leaving the step drops it.
    @Test func leavingTheFinishStepDropsTheToken() {
        let flow = makeFlow()
        flow.showFinishSignUp(.fixture())
        flow.show(.signIn)
        #expect(flow.finishSignUp == nil)
    }

    @Test func anExpiredStepGoesBackToSignInWithTheMessage() {
        let flow = makeFlow()
        flow.showFinishSignUp(.fixture())
        flow.returnToSignIn(.finishExpired)
        #expect(flow.step == .signIn)
        #expect(flow.signInNotice == .finishExpired)
        #expect(flow.finishSignUp == nil)
        flow.show(.signUp)
        #expect(flow.signInNotice == nil)
    }

    @Test func socialInviteRequiredPrefillsRequestAccess() {
        let flow = makeFlow()
        flow.showFinishSignUp(.fixture())
        flow.switchToRequestAccessAfterSocialSignIn()
        #expect(flow.step == .requestAccess)
        #expect(flow.showsInviteRequired)
        #expect(flow.inviteReason == .social)
        #expect(flow.requestAccess.email == "yasmine@gmail.com")
        #expect(flow.requestAccess.firstName == "Yasmine")
    }
}

@MainActor
struct SocialSignOutTests {
    @Test func signingOutAlsoSignsOutOfGoogle() {
        let tokens = InMemoryTokenStore(token: "t")
        let (session, _) = makeSession(tokens: tokens)
        let google = FakeGoogleSignIn()
        session.signOutOfProviders = { google.signOut() }
        session.didAuthenticate(token: "t", user: .fixture())
        session.signOut()
        #expect(google.signOuts == 1)
        #expect(tokens.load() == nil)
    }
}
