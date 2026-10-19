import SwiftUI

/// What the auth sheet needs besides the session: the auth calls and whether Taleed is invite-only.
struct AuthDependencies {
    let api: any AuthApi
    /// `betaMode` of `GET /config`.
    let isBetaMode: @MainActor () -> Bool
}

private struct AuthDependenciesKey: EnvironmentKey {
    static var defaultValue: AuthDependencies? { nil }
}

extension EnvironmentValues {
    var authDependencies: AuthDependencies? {
        get { self[AuthDependenciesKey.self] }
        set { self[AuthDependenciesKey.self] = newValue }
    }
}

/// The sheet every "Sign in" opens (`.taleedSheet` from the shell): the design-system bottom sheet
/// (handle, start-aligned Title 2 heading, close), as Android's sign-in sheet. It holds the four auth
/// forms; the links under each form move between them, as the website's auth pages do.
struct AuthSheetView: View {
    /// The router's `authEntry`; nil while the sheet closes.
    let entry: AuthEntry?
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(\.authDependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var flow: AuthFlowModel?

    var body: some View {
        TaleedBottomSheet(title: title, titleStyle: TaleedFont.title2, onClose: { dismiss() }, content: {
            if let flow {
                AuthStepView(flow: flow) { dismiss() }
            }
        })
        .animation(.easeInOut(duration: TaleedMotion.transitionMin), value: flow?.step)
        .onAppear {
            guard flow == nil, let dependencies else { return }
            flow = AuthFlowModel(entry: entry ?? .signIn, session: session, api: dependencies.api,
                                 isBetaMode: dependencies.isBetaMode)
        }
        // A link (`/r/{code}`) or another sign-in request while the sheet is already up.
        .onChange(of: entry) { _, newEntry in
            if let newEntry { flow?.open(newEntry) }
        }
    }

    private var title: String {
        switch flow?.step ?? .signIn {
        case .signIn: l10n.string(.authLoginTitle)
        case .signUp: l10n.string(.authRegisterTitle)
        case .forgotPassword: l10n.string(.authForgotTitle)
        case .requestAccess: l10n.string(.authRequestAccessTitle)
        }
    }
}

private struct AuthStepView: View {
    let flow: AuthFlowModel
    let onDone: () -> Void

    var body: some View {
        switch flow.step {
        case .signIn: SignInForm(viewModel: flow.signIn, flow: flow, onDone: onDone)
        case .signUp: SignUpFormView(viewModel: flow.signUp, flow: flow, onDone: onDone)
        case .forgotPassword: ForgotPasswordFormView(viewModel: flow.forgotPassword, flow: flow)
        case .requestAccess: RequestAccessFormView(viewModel: flow.requestAccess, flow: flow)
        }
    }
}

// MARK: - Shared pieces

/// The website's subtitle under the sheet title.
struct AuthSubtitle: View {
    let text: String

    var body: some View {
        Text(text)
            .taleedFont(TaleedFont.bodyRegular)
            .foregroundStyle(TaleedColor.textBody)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "No account yet? Create my account": one button, the action in the link colour.
struct AuthFooterLink: View {
    let prompt: String
    let action: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            let promptText = Text(prompt).foregroundStyle(TaleedColor.textBody)
            let actionText = Text(action).foregroundStyle(TaleedColor.brandPrimary).fontWeight(.semibold)
            Text("\(promptText) \(actionText)")
                .taleedFont(TaleedFont.bodyRegular)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: TaleedSize.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(prompt) \(action)")
    }
}

/// The form's message: an error alert, read out when it appears.
struct AuthFormMessage: View {
    let text: String
    var kind: TaleedFeedbackKind = .error
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        InlineAlert(kind: kind, title: text, actionTitle: actionTitle, action: action)
            .onAppear { AccessibilityNotification.Announcement(text).post() }
    }
}

extension View {
    /// An email field: no capitals, no corrections, the email keyboard.
    func emailInput() -> some View {
        keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    /// Keeps a field's text within `maxLength` UTF-16 code units as the member types or pastes.
    func limitLength(_ text: Binding<String>, to maxLength: Int) -> some View {
        onChange(of: text.wrappedValue) { _, newValue in
            let limited = AuthValidation.limited(newValue, to: maxLength)
            if limited != newValue { text.wrappedValue = limited }
        }
    }
}
