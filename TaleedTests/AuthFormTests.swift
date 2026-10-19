import Foundation
@testable import Taleed
import Testing

@MainActor
struct AuthValidationTests {
    @Test(arguments: [
        ("ab", false), ("abc", true), ("a.b-c_d", true), ("_abc", false), (".abc", false), ("Karim99", true),
        ("abc def", false), ("é-abc", false), (String(repeating: "a", count: 30), true),
        (String(repeating: "a", count: 31), false), ("  karim  ", true),
    ])
    func usernames(username: String, isValid: Bool) {
        #expect(AuthValidation.isValidUsername(username) == isValid)
    }

    @Test(arguments: [
        ("amina@example.com", true), (" amina@example.com ", true), ("amina@demo", false),
        ("amina demo@taleed.app", false), ("@taleed.app", false), ("", false),
    ])
    func emails(email: String, isValid: Bool) {
        #expect(AuthValidation.isValidEmail(email) == isValid)
    }

    @Test func emailOver255CharactersIsRefused() {
        let email = String(repeating: "a", count: 251) + "@x.dz"
        #expect(!AuthValidation.isValidEmail(email))
    }

    @Test(arguments: [("A", false), ("Al", true), ("  Al  ", true), ("   ", false),
                      (String(repeating: "b", count: 30), true), (String(repeating: "b", count: 31), false)])
    func nameParts(name: String, isValid: Bool) {
        #expect(AuthValidation.isValidNamePart(name) == isValid)
    }

    @Test func passwordsAreNotTrimmed() {
        #expect(AuthValidation.newPasswordProblem("1234567") == .tooShort)
        #expect(AuthValidation.newPasswordProblem("       a") == nil)
        #expect(AuthValidation.newPasswordProblem(String(repeating: "p", count: 128)) == nil)
        #expect(AuthValidation.newPasswordProblem(String(repeating: "p", count: 129)) == .tooLong)
    }

    @Test func referralCodes() {
        #expect(AuthValidation.referralCodeToSend("  a1b2c3d4 ") == "a1b2c3d4")
        #expect(AuthValidation.referralCodeToSend("   ") == nil)
        // A typo is sent as typed: the API ignores it (slice F).
        #expect(AuthValidation.referralCodeToSend("zz") == "zz")
        #expect(AuthValidation.referralCode(fromLink: "7DE5395A") == "7de5395a")
        #expect(AuthValidation.referralCode(fromLink: "not-a-code") == nil)
    }

    @Test func limitedKeepsWholeCharacters() {
        #expect(AuthValidation.limited("abcdef", to: 4) == "abcd")
        #expect(AuthValidation.limited("ab👍🏽", to: 3) == "ab")
        #expect(AuthValidation.limited("abc", to: 8) == "abc")
    }

    @Test func legalTextLinksTermsAndPrivacy() throws {
        let text = "En créant un compte, vous acceptez nos <terms>conditions</terms> et notre <privacy>politique</privacy>."
        #expect(LegalText.plain(text) == "En créant un compte, vous acceptez nos conditions et notre politique.")
        let attributed = LegalText.attributed(text, linkColor: .blue)
        let links = attributed.runs.compactMap(\.link)
        #expect(links.compactMap(LegalText.page(of:)) == [.terms, .privacy])
    }
}

@MainActor
struct SignUpViewModelTests {
    private let api = FakeAuthApi()
    private let tokens = InMemoryTokenStore()
    private let apiSession = ApiSession(environment: .fixture(), language: .fr, configuration: .init())

    private func makeViewModel(referralCode: String? = nil) -> (SignUpViewModel, SessionManager) {
        let session = SessionManager(api: FakeTaleedApi(), apiSession: apiSession, tokenStore: tokens)
        let viewModel = SignUpViewModel(api: api, session: session, referralCode: referralCode)
        return (viewModel, session)
    }

    private func fill(_ viewModel: SignUpViewModel) {
        viewModel.firstName = " Yasmine "
        viewModel.lastName = "Khelifi"
        viewModel.username = "yasmine.k"
        viewModel.email = " yasmine@example.com "
        viewModel.password = "a-long-password"
    }

    @Test func shortUsernameIsAFieldErrorBeforeAnyCall() async {
        let (viewModel, _) = makeViewModel()
        fill(viewModel)
        viewModel.username = "ab"

        let outcome = await viewModel.submit()

        #expect(outcome == .failed)
        #expect(viewModel.fieldErrors == [.username: .usernameInvalid])
        #expect(viewModel.firstFieldInError == .username)
        #expect(api.signUps.isEmpty)
    }

    @Test func emptyFormListsEveryRequiredField() async {
        let (viewModel, _) = makeViewModel()

        _ = await viewModel.submit()

        #expect(viewModel.fieldErrors == [.firstName: .nameLength, .lastName: .nameLength, .username: .usernameInvalid,
                                          .email: .emailInvalid, .password: .passwordTooShort])
        #expect(viewModel.firstFieldInError == .firstName)
    }

    @Test func successSendsTrimmedTextAndSignsIn() async {
        let (viewModel, session) = makeViewModel(referralCode: "7de5395a")
        fill(viewModel)

        let outcome = await viewModel.submit()

        #expect(outcome == .signedUp(firstName: "Yasmine"))
        #expect(api.signUps == [SignUpForm(firstName: "Yasmine", lastName: "Khelifi", username: "yasmine.k",
                                           email: "yasmine@example.com", password: "a-long-password",
                                           referralCode: "7de5395a")])
        #expect(session.isSignedIn)
        #expect(tokens.load() == "signup-token")
    }

    @Test func emailTakenOffersSignIn() async {
        let (viewModel, session) = makeViewModel()
        fill(viewModel)
        api.signUpResult = .failure(.failed(ApiFailure(status: 409, code: .emailTaken)))

        _ = await viewModel.submit()

        #expect(viewModel.fieldErrors == [.email: .emailTaken])
        #expect(viewModel.offersSignIn)
        #expect(!session.isSignedIn)
        viewModel.email = "other@example.com"
        #expect(!viewModel.offersSignIn)
        #expect(viewModel.fieldErrors.isEmpty)
    }

    @Test(arguments: [
        (ApiErrorCode.usernameTaken, 409, SignUpViewModel.Field.username, AuthFieldError.usernameTaken),
        (.invalidUsername, 400, .username, .usernameInvalid),
        (.passwordTooShort, 400, .password, .passwordTooShort),
        (.passwordTooLong, 400, .password, .passwordTooLong),
    ])
    func fieldErrorCodes(code: ApiErrorCode, status: Int, field: SignUpViewModel.Field, error: AuthFieldError) async {
        let (viewModel, _) = makeViewModel()
        fill(viewModel)
        api.signUpResult = .failure(.failed(ApiFailure(status: status, code: code)))

        _ = await viewModel.submit()

        #expect(viewModel.fieldErrors == [field: error])
        #expect(viewModel.message == nil)
    }

    @Test func invalidRequestHighlightsTheFieldsOfItsIssues() async {
        let (viewModel, _) = makeViewModel()
        fill(viewModel)
        api.signUpResult = .failure(.failed(ApiFailure(status: 400, code: .invalidRequest, issues: [
            ApiFieldIssue(path: "body.lastName", message: "Too small"),
        ])))

        _ = await viewModel.submit()

        #expect(viewModel.fieldErrors == [.lastName: .invalid])
    }

    @Test func inviteRequiredSwitchesToRequestAccess() async {
        let (viewModel, _) = makeViewModel()
        fill(viewModel)
        api.signUpResult = .failure(.failed(ApiFailure(status: 403, code: .inviteRequired)))

        #expect(await viewModel.submit() == .inviteRequired)
    }

    @Test(arguments: [
        (ApiError.network, FormMessage.key(.authErrorTimeout)),
        (ApiError.server(status: 500), FormMessage.key(.authErrorGeneric)),
        (ApiError.rateLimited(retryAfter: 600), FormMessage.error(.rateLimited(retryAfter: 600))),
        (ApiError.failed(ApiFailure(status: 403, code: .forbidden)), FormMessage.error(.failed(ApiFailure(status: 403, code: .forbidden)))),
    ])
    func formMessages(error: ApiError, message: FormMessage) async {
        let (viewModel, _) = makeViewModel()
        fill(viewModel)
        api.signUpResult = .failure(error)

        _ = await viewModel.submit()

        #expect(viewModel.message == message)
        #expect(viewModel.fieldErrors.isEmpty)
    }
}

@MainActor
struct SignInFormTests {
    @Test func malformedEmailIsCaughtBeforeTheCall() async {
        let api = FakeTaleedApi()
        let session = SessionManager(api: api, apiSession: ApiSession(environment: .fixture(), language: .fr, configuration: .init()),
                                     tokenStore: InMemoryTokenStore())
        let viewModel = SignInViewModel(session: session)
        viewModel.email = "amina"
        viewModel.password = "x"

        #expect(!(await viewModel.submit()))
        #expect(viewModel.emailError == .emailInvalid)
        viewModel.email = "amina@example.com"
        #expect(viewModel.emailError == nil)
    }

    @Test func longRateLimitSaysHowManyMinutes() {
        #expect(SignInViewModel.message(for: .rateLimited(retryAfter: 300)) == .error(.rateLimited(retryAfter: 300)))
        #expect(SignInViewModel.message(for: .rateLimited(retryAfter: 10)) == .key(.authErrorRateLimited))
        #expect(SignInViewModel.message(for: .banned) == nil)
    }
}

@MainActor
struct ForgotPasswordViewModelTests {
    @Test func alwaysShowsTheNeutralConfirmation() async {
        let api = FakeAuthApi()
        let viewModel = ForgotPasswordViewModel(api: api, email: " nobody@example.com ")

        await viewModel.submit()

        #expect(viewModel.isSent)
        #expect(api.resetEmails == ["nobody@example.com"])
    }

    @Test func malformedEmailIsAFieldError() async {
        let api = FakeAuthApi()
        let viewModel = ForgotPasswordViewModel(api: api, email: "nobody")

        await viewModel.submit()

        #expect(viewModel.emailError == .emailInvalid)
        #expect(!viewModel.isSent)
        #expect(api.resetEmails.isEmpty)
    }

    @Test func offlineShowsTheErrorWithoutConfirming() async {
        let api = FakeAuthApi()
        api.resetResult = .failure(.network)
        let viewModel = ForgotPasswordViewModel(api: api, email: "a@b.dz")

        await viewModel.submit()

        #expect(viewModel.message == .error(.network))
        #expect(!viewModel.isSent)
    }
}

@MainActor
struct RequestAccessViewModelTests {
    private func filled(_ api: FakeAuthApi) -> RequestAccessViewModel {
        let viewModel = RequestAccessViewModel(api: api, referralCode: "7de5395a")
        viewModel.firstName = " Yasmine "
        viewModel.lastName = " Khelifi"
        viewModel.email = "yasmine@example.com"
        return viewModel
    }

    @Test func joinsTheNamesAndDropsEmptyOptionalFields() async {
        let api = FakeAuthApi()
        let viewModel = filled(api)
        viewModel.phone = "  "

        await viewModel.submit()

        #expect(viewModel.done == .received)
        #expect(api.accessRequests == [AccessRequestForm(name: "Yasmine Khelifi", email: "yasmine@example.com", phone: nil,
                                                         message: nil, referralCode: "7de5395a")])
    }

    @Test func alreadyRequestedIsADoneState() async {
        let api = FakeAuthApi()
        api.accessResult = .failure(.failed(ApiFailure(status: 409, code: .alreadyRequested)))
        let viewModel = filled(api)

        await viewModel.submit()

        #expect(viewModel.done == .alreadyRequested)
    }

    @Test func accountExistsOffersSignIn() async {
        let api = FakeAuthApi()
        api.accessResult = .failure(.failed(ApiFailure(status: 409, code: .accountExists)))
        let viewModel = filled(api)

        await viewModel.submit()

        #expect(viewModel.done == nil)
        #expect(viewModel.offersSignIn)
        #expect(viewModel.formMessage == .key(.authRequestAccessAccountExists))
    }

    @Test func namesAreRequired() async {
        let api = FakeAuthApi()
        let viewModel = RequestAccessViewModel(api: api)

        await viewModel.submit()

        #expect(viewModel.fieldErrors == [.firstName: .nameLength, .lastName: .nameLength, .email: .emailInvalid])
        #expect(api.accessRequests.isEmpty)
    }
}

@MainActor
struct AuthFlowModelTests {
    private func makeFlow(entry: AuthEntry, betaMode: Bool = false) -> AuthFlowModel {
        let session = SessionManager(api: FakeTaleedApi(),
                                     apiSession: ApiSession(environment: .fixture(), language: .fr, configuration: .init()),
                                     tokenStore: InMemoryTokenStore())
        return AuthFlowModel(entry: entry, session: session, api: FakeAuthApi(), isBetaMode: { betaMode })
    }

    @Test func inviteLinkOpensSignUpWithTheCode() {
        let flow = makeFlow(entry: .signUp(referralCode: "7DE5395A"))
        #expect(flow.step == .signUp)
        #expect(flow.signUp.referralCode == "7de5395a")
    }

    @Test func inviteLinkDuringBetaOpensRequestAccessWithTheCode() {
        let flow = makeFlow(entry: .signUp(referralCode: "7de5395a"), betaMode: true)
        #expect(flow.step == .requestAccess)
        #expect(flow.requestAccess.referralCode == "7de5395a")
    }

    @Test func createAccountDuringBetaOpensRequestAccess() {
        let flow = makeFlow(entry: .signIn, betaMode: true)
        flow.show(.signUp)
        #expect(flow.step == .requestAccess)
    }

    @Test func emailFollowsTheMemberBetweenSteps() {
        let flow = makeFlow(entry: .signIn)
        flow.signIn.email = "amina@example.com"
        flow.show(.forgotPassword)
        #expect(flow.forgotPassword.email == "amina@example.com")
        flow.show(.signUp)
        #expect(flow.signUp.email == "amina@example.com")
    }

    @Test func inviteRequiredCarriesTheSignUpForm() {
        let flow = makeFlow(entry: .signUp(referralCode: nil))
        flow.signUp.firstName = "Yasmine"
        flow.signUp.lastName = "Khelifi"
        flow.signUp.email = "y@example.com"
        flow.switchToRequestAccess()
        #expect(flow.step == .requestAccess)
        #expect(flow.showsInviteRequired)
        #expect(flow.requestAccess.firstName == "Yasmine")
        #expect(flow.requestAccess.email == "y@example.com")
    }
}

@MainActor
struct WelcomeGateTests {
    @Test func showsUntilBrowsingThenAgainAfterSignOut() throws {
        let defaults = try #require(UserDefaults(suiteName: "WelcomeGateTests"))
        defaults.removePersistentDomain(forName: "WelcomeGateTests")
        let gate = WelcomeGate(defaults: defaults)
        #expect(gate.isVisible)

        gate.complete()
        #expect(!gate.isVisible)
        #expect(!WelcomeGate(defaults: defaults).isVisible)

        gate.showAfterSignOut()
        #expect(gate.isVisible)
        #expect(WelcomeGate(defaults: defaults).isVisible)

        gate.skipForLink()
        #expect(!gate.isVisible)
        #expect(WelcomeGate(defaults: defaults).isVisible)
        defaults.removePersistentDomain(forName: "WelcomeGateTests")
    }
}
