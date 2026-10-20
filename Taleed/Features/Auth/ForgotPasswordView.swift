import SwiftUI

/// Forgot password (website `forgot-password-form.tsx`): subtitle, email, "Send link" (mint Secondary
/// Large, the main CTA of every auth sheet, decision D-10), and once sent the neutral "if an account exists for this email,
/// a link has been sent". The link opens the website's reset page (decision 2).
struct ForgotPasswordFormView: View {
    @Bindable var viewModel: ForgotPasswordViewModel
    let flow: AuthFlowModel
    @Environment(LanguageManager.self) private var l10n
    @FocusState private var emailFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSize.bottomSheetGap) {
            AuthSubtitle(text: l10n.string(.authForgotSubtitle))

            TaleedTextField(label: l10n.string(.authEmail), text: $viewModel.email, leadingIcon: .envelope,
                            error: viewModel.emailError.map(l10n.text(for:)), focus: $emailFocused)
                .textContentType(.emailAddress)
                .emailInput()
                .limitLength($viewModel.email, to: AuthRules.emailMaxLength)
                .submitLabel(.send)
                .onSubmit(submit)
                .disabled(viewModel.isLoading)

            if viewModel.isSent {
                AuthFormMessage(text: l10n.string(.authResetSent), kind: .success)
            } else if let message = viewModel.message {
                AuthFormMessage(text: l10n.text(for: message))
            }

            TaleedButton(title: l10n.string(.authSendResetLink), kind: .secondary, size: .large,
                         isLoading: viewModel.isLoading, isFullWidth: true, action: submit)
                .disabled(!viewModel.canSubmit && !viewModel.isLoading)

            AuthFooterLink(prompt: l10n.string(.authHaveAccount), action: l10n.string(.authLoginCta)) {
                flow.show(.signIn)
            }
        }
        .padding(.bottom, TaleedSpacing.s8)
        .autofocus($emailFocused)
    }

    private func submit() {
        Task {
            await viewModel.submit()
            if viewModel.emailError != nil { emailFocused = true }
        }
    }
}
