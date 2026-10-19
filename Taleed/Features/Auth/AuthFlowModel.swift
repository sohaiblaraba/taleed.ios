import Foundation
import Observation

/// The auth sheet's steps: sign in, sign up, forgot password and request access. The sheet opens on
/// the step the router asks for; the links at the bottom of each form move between them, as the
/// website's auth pages do. During the invite-only period (`betaMode`), "Create an account" leads to
/// the request-access form.
@MainActor
@Observable
final class AuthFlowModel {
    enum Step: Equatable, Sendable {
        case signIn, signUp, forgotPassword, requestAccess
    }

    private(set) var step: Step
    /// A sign-up answered `invite_required`: the request-access form says why it shows.
    private(set) var showsInviteRequired = false

    let signIn: SignInViewModel
    let signUp: SignUpViewModel
    let forgotPassword: ForgotPasswordViewModel
    let requestAccess: RequestAccessViewModel

    @ObservationIgnored private let isBetaMode: () -> Bool

    init(entry: AuthEntry, session: SessionManager, api: AuthApi, isBetaMode: @escaping () -> Bool) {
        self.isBetaMode = isBetaMode
        var referralCode: String?
        if case let .signUp(code) = entry { referralCode = code.flatMap(AuthValidation.referralCode(fromLink:)) }
        signIn = SignInViewModel(session: session)
        signUp = SignUpViewModel(api: api, session: session, referralCode: referralCode)
        forgotPassword = ForgotPasswordViewModel(api: api)
        requestAccess = RequestAccessViewModel(api: api, referralCode: referralCode)
        switch entry {
        case .signIn: step = .signIn
        case .signUp: step = isBetaMode() ? .requestAccess : .signUp
        }
    }

    /// Moves to another step, taking the email typed so far when that step's field is empty.
    func show(_ target: Step) {
        let email = currentEmail
        let target = target == .signUp && isBetaMode() ? .requestAccess : target
        if target != .requestAccess { showsInviteRequired = false }
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
    }

    private var currentEmail: String {
        switch step {
        case .signIn: signIn.email
        case .signUp: signUp.email
        case .forgotPassword: forgotPassword.email
        case .requestAccess: requestAccess.email
        }
    }
}
