import AuthenticationServices
import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// Slice G: Sign in with Google and Apple.

/// A Google SDK that answers from a canned result and records the nonce it was given.
@MainActor
final class FakeGoogleSignIn: GoogleSignInClient {
    var isConfigured = true
    /// Built from the nonce, so the credential carries the nonce the flow made.
    var answer: (String) -> SocialProviderResult = { nonce in
        .credential(SocialCredential(provider: .google, idToken: "google-id-token", nonce: nonce))
    }
    private(set) var nonces: [String] = []
    private(set) var signOuts = 0

    func signIn(nonce: String) async -> SocialProviderResult {
        nonces.append(nonce)
        return answer(nonce)
    }

    func signOut() { signOuts += 1 }
    func handle(_ url: URL) -> Bool { false }
}

extension SocialProfile {
    static func fixture(firstName: String? = "Yasmine", lastName: String? = "Benali",
                        referralCode: String? = nil) -> SocialProfile {
        SocialProfile(signupToken: "signup-1", expiresAt: Date(timeIntervalSinceNow: 900), email: "yasmine@gmail.com",
                      username: "yasmine.benali", firstName: firstName, lastName: lastName, referralCode: referralCode)
    }
}

@MainActor
func makeSession(tokens: InMemoryTokenStore = InMemoryTokenStore()) -> (SessionManager, ApiSession) {
    let apiSession = ApiSession(environment: .fixture(), language: .fr, configuration: .init())
    return (SessionManager(api: FakeTaleedApi(), apiSession: apiSession, tokenStore: tokens), apiSession)
}

struct SocialNonceTests {
    @Test func aNonceIs32RandomBytesInBase64URL() {
        let nonce = SocialNonce.make()
        // 32 bytes: 43 base64 characters without padding.
        #expect(nonce.count == 43)
        #expect(nonce.wholeMatch(of: /[A-Za-z0-9_-]+/) != nil)
        #expect(Data(base64Encoded: nonce.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + "=")?.count == 32)
    }

    @Test func eachAttemptHasItsOwnNonce() {
        let nonces = Set((0..<50).map { _ in SocialNonce.make() })
        #expect(nonces.count == 50)
    }

    @Test func appleGetsTheLowercaseHexSHA256() {
        #expect(SocialNonce.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let request = ASAuthorizationAppleIDProvider().createRequest()
        AppleSignIn.configure(request, nonce: "abc")
        #expect(request.nonce == SocialNonce.sha256Hex("abc"))
        #expect(request.requestedScopes == [.fullName, .email])
    }
}

struct SocialAvailabilityTests {
    private func features(google: Bool, apple: Bool) -> RemoteFeatures {
        RemoteFeatures(googleSignIn: google, appleSignIn: apple)
    }

    /// Guideline 4.8: a release build shows Google only with Apple.
    @Test func releaseShowsGoogleOnlyWithApple() {
        #expect(SocialAvailability.of(features(google: true, apple: true), googleConfigured: true,
                                      allowsGoogleWithoutApple: false) == SocialAvailability(apple: true, google: true))
        #expect(SocialAvailability.of(features(google: true, apple: false), googleConfigured: true,
                                      allowsGoogleWithoutApple: false).isEmpty)
        #expect(SocialAvailability.of(features(google: false, apple: true), googleConfigured: true,
                                      allowsGoogleWithoutApple: false) == SocialAvailability(apple: true, google: false))
    }

    @Test func debugMayShowGoogleAlone() {
        #expect(SocialAvailability.of(features(google: true, apple: false), googleConfigured: true,
                                      allowsGoogleWithoutApple: true) == SocialAvailability(apple: false, google: true))
    }

    @Test func noClientIDNoGoogleButton() {
        #expect(SocialAvailability.of(features(google: true, apple: true), googleConfigured: false,
                                      allowsGoogleWithoutApple: true) == SocialAvailability(apple: true, google: false))
    }
}

struct SocialAnswerDecodingTests {
    private let me = Me(id: "u9", username: "yasmine", displayName: "@yasmine", avatarUrl: nil, isVerified: false,
                        isOfficial: false, email: "y@gmail.com", emailVerified: true, hasPassword: false, name: "Yasmine B",
                        firstName: "Yasmine", lastName: "B", bio: nil, phone: nil, phoneVerified: false, wilaya: nil,
                        usernameNextChangeAt: nil, preferences: Preferences(newsletter: false), createdAt: .now,
                        counts: MeCounts(unreadMessages: 0, unreadNotifications: 0))

    @Test func signedInCarriesTheSession() throws {
        let result = SocialSignInResult(status: .signedIn, session: AuthSession(token: "tok", user: me), profile: nil)
        guard case let .session(token, user) = try SocialSignInAnswer(result) else {
            Issue.record("expected a session")
            return
        }
        #expect(token == "tok")
        #expect(user.id == "u9")
    }

    @Test func profileRequiredCarriesThePrefill() throws {
        let suggestion = SocialSuggestion(username: "yasmine.b", firstName: nil, lastName: "B", email: "y@privaterelay.appleid.com",
                                          referralCode: "a1b2c3d4")
        let profile = SocialProfileRequired(signupToken: "st", expiresAt: .now, suggested: suggestion)
        let answer = try SocialSignInAnswer(SocialSignInResult(status: .profileRequired, session: nil, profile: profile))
        guard case let .profileRequired(decoded) = answer else {
            Issue.record("expected the finish step")
            return
        }
        #expect(decoded.signupToken == "st")
        #expect(decoded.email == "y@privaterelay.appleid.com")
        #expect(decoded.firstName == nil)
        #expect(decoded.referralCode == "a1b2c3d4")
    }

    /// An unknown status is a bug to report, not a crash: an error the form shows as "did not go through".
    @Test func anUnknownStatusIsAnError() throws {
        let unknown = SocialSignInResult(status: .unknownDefaultOpenApi, session: nil, profile: nil)
        #expect(throws: ErrorResponse.self) { try SocialSignInAnswer(unknown) }
        let incomplete = SocialSignInResult(status: .signedIn, session: nil, profile: nil)
        do {
            _ = try SocialSignInAnswer(incomplete)
            Issue.record("expected an error")
        } catch let error as ErrorResponse {
            let apiError = Taleed.ApiError.from(error)
            #expect(SocialSignInViewModel.messageKey(for: apiError) == .authSocialErrorFailed)
        }
    }
}

struct AppleCredentialTests {
    @Test func theTokenAndCodeAreUTF8AndTheNameIsForwarded() {
        var name = PersonNameComponents()
        name.givenName = "Yasmine"
        name.familyName = " "
        let credential = AppleSignIn.credential(idToken: Data("id.token.jwt".utf8), authorizationCode: Data("code-1".utf8),
                                                fullName: name, email: "y@privaterelay.appleid.com", nonce: "raw-nonce")
        #expect(credential == SocialCredential(provider: .apple, idToken: "id.token.jwt", nonce: "raw-nonce",
                                               authorizationCode: "code-1", firstName: "Yasmine", lastName: nil,
                                               prefill: SocialPrefill(email: "y@privaterelay.appleid.com", firstName: "Yasmine")))
    }

    @Test func cancelIsRecognised() {
        #expect(AppleSignIn.isCancel(ASAuthorizationError(.canceled)))
        #expect(!AppleSignIn.isCancel(ASAuthorizationError(.failed)))
        #expect(AppleSignIn.result(of: .failure(ASAuthorizationError(.canceled)), nonce: "n") == .canceled)
        #expect(AppleSignIn.result(of: .failure(ASAuthorizationError(.failed)), nonce: "n") == .failed)
    }
}

@MainActor
struct SocialSignInViewModelTests {
    private let api = FakeAuthApi()
    private let google = FakeGoogleSignIn()

    @Test func googleSendsTheRawNonceAndSignsIn() async {
        let tokens = InMemoryTokenStore()
        let (session, apiSession) = makeSession(tokens: tokens)
        let model = SocialSignInViewModel(api: api, session: session, google: google)
        #expect(await model.signInWithGoogle() == .signedIn)
        #expect(google.nonces.count == 1)
        #expect(api.socialCredentials.first?.nonce == google.nonces.first)
        #expect(api.socialCredentials.first?.provider == .google)
        #expect(session.isSignedIn)
        #expect(tokens.load() == "social-token")
        #expect(apiSession.token == "social-token")
        #expect(model.pending == nil)
    }

    @Test func aNewMemberGoesToTheFinishStep() async {
        let profile = SocialProfile.fixture()
        api.socialResult = .success(.profileRequired(profile))
        let model = SocialSignInViewModel(api: api, session: makeSession().0, google: google)
        #expect(await model.signInWithGoogle() == .profileRequired(profile))
    }

    /// Closing Google's or Apple's sheet stays on the screen, silently, and calls no API.
    @Test func cancelIsSilent() async {
        google.answer = { _ in .canceled }
        let model = SocialSignInViewModel(api: api, session: makeSession().0, google: google)
        #expect(await model.signInWithGoogle() == .stayed)
        #expect(model.message == nil)
        #expect(await model.completeApple(.canceled) == .stayed)
        #expect(model.message == nil)
        #expect(api.socialCredentials.isEmpty)
    }

    @Test func anSDKFailureSaysItDidNotGoThrough() async {
        google.answer = { _ in .failed }
        let model = SocialSignInViewModel(api: api, session: makeSession().0, google: google)
        #expect(await model.signInWithGoogle() == .stayed)
        #expect(model.message == .key(.authSocialErrorFailed))
    }

    @Test func appleSendsTheCodeAndName() async {
        let model = SocialSignInViewModel(api: api, session: makeSession().0, google: nil)
        let credential = SocialCredential(provider: .apple, idToken: "apple-jwt", nonce: "n1", authorizationCode: "c1",
                                          firstName: "Yasmine", lastName: "Benali")
        #expect(await model.completeApple(.credential(credential)) == .signedIn)
        #expect(api.socialCredentials == [credential])
    }

    /// A suspended member: the token is stored and the suspended screen shows, as for email sign-in.
    @Test func bannedWithATokenKeepsTheSuspendedSession() async {
        api.socialResult = .success(.suspended(token: "suspended-token"))
        let tokens = InMemoryTokenStore()
        let (session, _) = makeSession(tokens: tokens)
        let model = SocialSignInViewModel(api: api, session: session, google: google)
        #expect(await model.signInWithGoogle() == .suspended)
        #expect(session.state == .suspended)
        #expect(session.hasSuspendedSession)
        #expect(tokens.load() == "suspended-token")
        #expect(model.message == nil)
    }

    @Test func bannedWithoutATokenShowsTheSuspendedScreenWithoutASession() async {
        api.socialResult = .failure(.banned)
        let (session, _) = makeSession()
        let model = SocialSignInViewModel(api: api, session: session, google: google)
        #expect(await model.signInWithGoogle() == .suspended)
        #expect(session.state == .suspended)
        #expect(!session.hasSuspendedSession)
    }

    /// `invite_required` carries what the provider gave, for the request-access form.
    @Test func inviteRequiredOpensRequestAccessWithTheProvidersProfile() async {
        api.socialResult = .failure(failure(.inviteRequired, status: 403))
        let prefill = SocialPrefill(email: "yasmine@gmail.com", firstName: "Yasmine", lastName: "Benali")
        google.answer = { nonce in
            .credential(SocialCredential(provider: .google, idToken: "t", nonce: nonce, prefill: prefill))
        }
        let model = SocialSignInViewModel(api: api, session: makeSession().0, google: google)
        #expect(await model.signInWithGoogle() == .inviteRequired(prefill))
    }

    @Test func featureDisabledHidesTheButton() async {
        api.socialResult = .failure(failure(.featureDisabled, status: 503))
        var disabled: [SocialProviderKind] = []
        let model = SocialSignInViewModel(api: api, session: makeSession().0, google: google) { disabled.append($0) }
        #expect(await model.signInWithGoogle() == .stayed)
        #expect(disabled == [.google])
        #expect(model.message == .key(.authSocialErrorDisabled))
    }

    @Test(arguments: [
        (Taleed.ApiError.failed(ApiFailure(status: 400, code: .socialTokenInvalid)), L10nKey.authSocialErrorFailed),
        (.failed(ApiFailure(status: 403, code: .socialEmailUnverified)), .authSocialErrorEmailUnverified),
        (.failed(ApiFailure(status: 403, code: .forbidden)), .authSocialErrorRefused),
        (.failed(ApiFailure(status: 503, code: .featureDisabled)), .authSocialErrorDisabled),
        (.failed(ApiFailure(status: 403, code: .inviteRequired)), .authSocialErrorInviteRequired),
        (.failed(ApiFailure(status: 400, code: .invalidRequest)), .authSocialErrorFailed),
        (.rateLimited(retryAfter: 300), .authSocialErrorRateLimited),
        (.network, .commonErrorNetwork),
        (.server(status: 500), .authSocialErrorFailed),
    ])
    func errorMessages(error: Taleed.ApiError, key: L10nKey) {
        #expect(SocialSignInViewModel.messageKey(for: error) == key)
    }

    @Test func refusedEmailShowsTheMessageAndStays() async {
        api.socialResult = .failure(failure(.socialEmailUnverified, status: 403))
        let (session, _) = makeSession()
        let model = SocialSignInViewModel(api: api, session: session, google: google)
        #expect(await model.signInWithGoogle() == .stayed)
        #expect(model.message == .key(.authSocialErrorEmailUnverified))
        #expect(!session.isSignedIn)
    }
}

@MainActor
struct FinishSignUpViewModelTests {
    private let api = FakeAuthApi()

    private func makeModel(profile: SocialProfile = .fixture(), linkCode: String? = nil) -> (FinishSignUpViewModel, SessionManager) {
        let (session, _) = makeSession()
        return (FinishSignUpViewModel(profile: profile, linkReferralCode: linkCode, api: api, session: session), session)
    }

    @Test func prefillsFromTheProvider() {
        let (model, _) = makeModel(profile: .fixture(firstName: nil, referralCode: "a1b2c3d4"))
        #expect(model.firstName.isEmpty)
        #expect(model.lastName == "Benali")
        #expect(model.username == "yasmine.benali")
        #expect(model.referralCode == "a1b2c3d4")
    }

    @Test func theInviteLinkCodeWinsOverTheAccessRequests() {
        let (model, _) = makeModel(profile: .fixture(referralCode: "a1b2c3d4"), linkCode: "7de5395a")
        #expect(model.referralCode == "7de5395a")
    }

    @Test func checksTheSignUpRulesOnTheDevice() async {
        let (model, _) = makeModel(profile: .fixture(firstName: nil))
        model.username = "_bad"
        #expect(await model.submit() == .failed)
        #expect(model.fieldErrors == [.firstName: .nameLength, .username: .usernameStart])
        #expect(api.completions.isEmpty)
    }

    @Test func createsTheAccountAndSignsIn() async {
        let (model, session) = makeModel()
        model.firstName = " Yasmine "
        model.referralCode = "  "
        #expect(await model.submit() == .signedUp(firstName: "Yasmine"))
        #expect(api.completions == [SocialSignUpForm(signupToken: "signup-1", firstName: "Yasmine", lastName: "Benali",
                                                     username: "yasmine.benali", referralCode: nil)])
        #expect(session.isSignedIn)
    }

    /// `username_taken` is a field error; the token stays valid for the next try.
    @Test func usernameTakenKeepsTheToken() async {
        api.completeResults = [.failure(failure(.usernameTaken)), .success(("t", .fixture(username: "yasmine.b2")))]
        let (model, _) = makeModel()
        #expect(await model.submit() == .failed)
        #expect(model.fieldErrors == [.username: .usernameTaken])
        model.username = "yasmine.b2"
        #expect(model.fieldErrors.isEmpty)
        #expect(await model.submit() == .signedUp(firstName: "Yasmine"))
        #expect(api.completions.map(\.signupToken) == ["signup-1", "signup-1"])
    }

    @Test(arguments: [
        (ApiErrorCode.socialSignupExpired, 400, FinishSignUpViewModel.Outcome.expired),
        (.emailTaken, 409, .emailTaken),
        (.inviteRequired, 403, .inviteRequired),
    ])
    func errorsThatLeaveTheStep(code: ApiErrorCode, status: Int, outcome: FinishSignUpViewModel.Outcome) async {
        api.completeResults = [.failure(failure(code, status: status))]
        let (model, session) = makeModel()
        #expect(await model.submit() == outcome)
        #expect(!session.isSignedIn)
    }

    @Test func errorsThatStayOnTheStep() async {
        api.completeResults = [.failure(failure(.invalidUsername, status: 400)),
                               .failure(failure(.forbidden, status: 403)),
                               .failure(.rateLimited(retryAfter: 60)),
                               .failure(invalid("body.lastName"))]
        let (model, _) = makeModel()
        #expect(await model.submit() == .failed)
        #expect(model.fieldErrors == [.username: .usernameInvalid])
        #expect(await model.submit() == .failed)
        #expect(model.message == .key(.authSocialErrorRefused))
        #expect(await model.submit() == .failed)
        #expect(model.message == .key(.authSocialErrorRateLimited))
        #expect(await model.submit() == .failed)
        #expect(model.fieldErrors == [.lastName: .invalid])
    }
}
