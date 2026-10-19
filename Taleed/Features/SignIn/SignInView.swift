import SwiftUI

/// Opened as a sheet from every "Sign in" button.
struct SignInView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SignInViewModel?

    var body: some View {
        VStack(spacing: 0) {
            TaleedAppBar(
                title: l10n.string(.authSignIn),
                actions: [AppBarAction(icon: .x, accessibilityLabel: l10n.string(.commonClose),
                                       color: TaleedColor.textPrimary) { dismiss() }]
            )
            if let viewModel {
                SignInForm(viewModel: viewModel) { dismiss() }
            }
            Spacer(minLength: 0)
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .onAppear {
            if viewModel == nil { viewModel = SignInViewModel(session: session) }
        }
    }
}

private struct SignInForm: View {
    @Bindable var viewModel: SignInViewModel
    let onDone: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaleedLayout.formFieldGap) {
                fields
                    // The fields lock while signing in; the button stays outside this scope so it keeps
                    // the Default colours with its spinner (it ignores taps while loading).
                    .disabled(viewModel.isLoading)

                if let errorKey = viewModel.errorKey {
                    InlineAlert(kind: .error, title: l10n.string(errorKey))
                }

                TaleedButton(title: l10n.string(.authSignIn), kind: .secondary, size: .large,
                             isLoading: viewModel.isLoading, isFullWidth: true, action: submit)
                    .disabled(!viewModel.canSubmit && !viewModel.isLoading)
            }
            .padding(.top, TaleedLayout.FormBodyPadding.top)
            .padding(.horizontal, TaleedLayout.FormBodyPadding.x)
            .padding(.bottom, TaleedLayout.FormBodyPadding.bottom)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: TaleedLayout.formFieldGap) {
            TaleedTextField(label: l10n.string(.authEmail), text: $viewModel.email, leadingIcon: .envelope,
                            focus: $emailFocused)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { passwordFocused = true }
            TaleedTextField(label: l10n.string(.authPassword), text: $viewModel.password, leadingIcon: .lockKey,
                            isSecure: true, focus: $passwordFocused)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit(submit)
        }
    }

    private func submit() {
        Task {
            if await viewModel.submit() { onDone() }
        }
    }
}
