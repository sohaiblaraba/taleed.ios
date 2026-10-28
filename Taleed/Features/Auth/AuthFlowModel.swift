import Foundation
import Observation

/// The auth sheet's steps: sign in, sign up, forgot password and request access. The sheet opens on
/// the step the router asks for; the links at the bottom of each form move between them, as the
/// website's auth pages do. During the invite-only period (`betaMode`), "Create an account" leads to
/// the request-access form. A first Google or Apple sign-in leads to the finish step (slice G).
@MainActor
@Observable
final class AuthFlowModel {
    enum Step: Equatable, Sendable {
        case signIn, signUp, forgotPassword, requestAccess, finishSignUp
    }

    /// Why the request-access form shows after `invite_required`.
    enum InviteReason: Equatable, Sendable {
        case emailSignUp
        /// A Google or Apple sign-up: request access, then continue with the provider again.
        case social
    }

    /// A notice on the sign-in form after the finish step sent the member back.
    enum SignInNotice: Equatable, Sendable {
        /// `social_signup_expired`.
        case finishExpired
        /// `email_taken`: sign in with the provider again.
        case emailTaken
    }

    private(set) var step: Step
    /// A sign-up answered `invite_required`: the request-access form says why it shows.
    private(set) var showsInviteRequired = false
    private(set) var inviteReason = InviteReason.emailSignUp
    private(set) var signInNotice: SignInNotice?

    let signIn: SignInViewModel
    let signUp: SignUpViewModel
    let forgotPassword: ForgotPasswordViewModel
    let requestAccess: RequestAccessViewModel
    let social: SocialSignInViewModel
    /// The finish step of a new Google or Apple member; nil on the other steps.
    private(set) var finishSignUp: FinishSignUpViewModel?

    @ObservationIgnored private let isBetaMode: () -> Bool
    @ObservationIgnored private let api: AuthApi
    @ObservationIgnored private let session: SessionManager
    /// The code of the invite link the app opened (`/r/{code}`), for the finish step.
    @ObservationIgnored private var linkReferralCode: String?

    init(entry: AuthEntry, session: SessionManager, api: AuthApi, isBetaMode: @escaping () -> Bool,
         google: (any GoogleSignInClient)? = nil, onSocialFeatureDisabled: @escaping (SocialProviderKind) -> Void = { _ in }) {
        self.isBetaMode = isBetaMode
        self.api = api
        self.session = session
        var referralCode: String?
        if case let .signUp(code) = entry { referralCode = code.flatMap(AuthValidation.referralCode(fromLink:)) }
        linkReferralCode = referralCode
        social = SocialSignInViewModel(api: api, session: session, google: google, onFeatureDisabled: onSocialFeatureDisabled)
        signIn = SignInViewModel(session: session)
        signUp = SignUpViewModel(api: api, session: session, referralCode: referralCode)
        forgotPassword = ForgotPasswordViewModel(api: api)
        requestAccess = RequestAccessViewModel(api: api, referralCode: referralCode)
        switch entry {
        case .signIn: step = .signIn
        case .signUp: step = isBetaMode() ? .requestAccess : .signUp
        }
    }

    /// The router asked for another entry while the sheet is open: an `/r/{code}` link or a sign-up
    /// button opens sign-up (request access while invite-only) with the link's code, which replaces
    /// any code typed so far (screens.md §1.2).
    func open(_ entry: AuthEntry) {
        switch entry {
        case .signIn:
            show(.signIn)
        case let .signUp(code):
            if let code = code.flatMap(AuthValidation.referralCode(fromLink:)) {
                linkReferralCode = code
                signUp.referralCode = code
                requestAccess.referralCode = code
                finishSignUp?.referralCode = code
            }
            show(.signUp)
        }
    }

    /// Moves to another step, taking the email typed so far when that step's field is empty.
    func show(_ target: Step) {
        let email = currentEmail
        let target = target == .signUp && isBetaMode() ? .requestAccess : target
        if target != .requestAccess { showsInviteRequired = false }
        if target != .signIn { signInNotice = nil }
        // The finish step's token is single-use and kept in memory only: leaving the step drops it.
        if target != .finishSignUp { finishSignUp = nil }
        social.clearMessage()
        switch target {
        case .signIn where signIn.email.isEmpty: signIn.email = email
        case .signUp where signUp.email.isEmpty: signUp.email = email
        case .forgotPassword where forgotPassword.email.isEmpty: forgotPassword.email = email
        case .requestAccess where requestAccess.email.isEmpty: requestAccess.email = email
        default: break
        }
        step = target
    }

    /// `invite_required`: the request-access form, with what the member typed in sign-up.
    func switchToRequestAccess() {
        if requestAccess.firstName.isEmpty { requestAccess.firstName = signUp.firstName }
        if requestAccess.lastName.isEmpty { requestAccess.lastName = signUp.lastName }
        if requestAccess.referralCode.isEmpty { requestAccess.referralCode = signUp.referralCode }
        show(.requestAccess)
        showsInviteRequired = true
        inviteReason = .emailSignUp
    }

    /// `invite_required` from Google or Apple: the request-access form, with the email and names the
    /// finish step had, or else those the provider gave (`prefill`).
    func switchToRequestAccessAfterSocialSignIn(prefill: SocialPrefill = SocialPrefill()) {
        var prefill = prefill
        if let finish = finishSignUp {
            prefill = SocialPrefill(email: finish.profile.email, firstName: AuthValidation.trimmed(finish.firstName),
                                    lastName: AuthValidation.trimmed(finish.lastName))
            if requestAccess.referralCode.isEmpty { requestAccess.referralCode = finish.referralCode }
        }
        if requestAccess.email.isEmpty, let email = prefill.email { requestAccess.email = email }
        if requestAccess.firstName.isEmpty, let firstName = prefill.firstName { requestAccess.firstName = firstName }
        if requestAccess.lastName.isEmpty, let lastName = prefill.lastName { requestAccess.lastName = lastName }
        show(.requestAccess)
        showsInviteRequired = true
        inviteReason = .social
    }

    /// `profile_required`: the finish step, prefilled.
    func showFinishSignUp(_ profile: SocialProfile) {
        let finish = FinishSignUpViewModel(profile: profile, linkReferralCode: linkReferralCode, api: api, session: session)
        show(.finishSignUp)
        finishSignUp = finish
    }

    /// The finish step ended without an account: back to sign-in with why.
    func returnToSignIn(_ notice: SignInNotice) {
        show(.signIn)
        signInNotice = notice
    }

    private var currentEmail: String {
        switch step {
        case .signIn: signIn.email
        case .signUp: signUp.email
        case .forgotPassword: forgotPassword.email
        case .requestAccess: requestAccess.email
        case .finishSignUp: ""
        }
    }
}
