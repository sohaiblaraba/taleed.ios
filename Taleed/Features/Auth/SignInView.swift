import SwiftUI

/// Sign in (website `login-form.tsx`): subtitle, email, password with "Forgot password?", the error,
/// "Log in" (Secondary Large), then "No account yet? Create my account".
struct SignInForm: View {
    @Bindable var viewModel: SignInViewModel
    let flow: AuthFlowModel
    let onDone: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    var body: some View {
        // The sheet's gap (18) between the blocks, as on Android.
        VStack(alignment: .leading, spacing: TaleedSize.bottomSheetGap) {
            AuthSubtitle(text: l10n.string(.authLoginSubtitle))

            fields
                // The fields lock while signing in; the button stays outside this scope so it keeps
                // the Default colours with its spinner (it ignores taps while loading).
                .disabled(viewModel.isLoading)

            if let message = viewModel.message {
                AuthFormMessage(text: l10n.text(for: message))
            }

            TaleedButton(title: l10n.string(.authLoginCta), kind: .secondary, size: .large,
                         isLoading: viewModel.isLoading, isFullWidth: true, action: submit)
                .disabled(!viewModel.canSubmit && !viewModel.isLoading)

            AuthFooterLink(prompt: l10n.string(.authNoAccount), action: l10n.string(.authRegisterCta)) {
                flow.show(.signUp)
            }
        }
        .padding(.bottom, TaleedSpacing.s8)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: TaleedSize.bottomSheetGap) {
            TaleedTextField(label: l10n.string(.authEmail), text: $viewModel.email, leadingIcon: .envelope,
                            error: viewModel.emailError.map(l10n.text(for:)), focus: $emailFocused)
                .textContentType(.username)
                .emailInput()
                .limitLength($viewModel.email, to: AuthRules.emailMaxLength)
                .submitLabel(.next)
                .onSubmit { passwordFocused = true }
            VStack(alignment: .trailing, spacing: TaleedSpacing.s4) {
                TaleedTextField(label: l10n.string(.authPassword), text: $viewModel.password, leadingIcon: .lockKey,
                                isSecure: true, focus: $passwordFocused)
                    .textContentType(.password)
                    .limitLength($viewModel.password, to: AuthRules.passwordMaxLength)
                    .submitLabel(.go)
                    .onSubmit(submit)
                TaleedButton(title: l10n.string(.authForgotPassword), kind: .hyperlink, size: .small) {
                    flow.show(.forgotPassword)
                }
            }
        }
    }

    private func submit() {
        Task {
            if await viewModel.submit() {
                onDone()
            } else if viewModel.emailError != nil {
                emailFocused = true
            }
        }
    }
}
