import SwiftUI

/// Opened with `.taleedSheet` from every "Sign in" button: the design-system bottom sheet (handle,
/// start-aligned Title 2 heading, close), as Android's SignInSheet.
struct SignInView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SignInViewModel?

    var body: some View {
        TaleedBottomSheet(title: l10n.string(.authSignIn), titleStyle: TaleedFont.title2, onClose: { dismiss() }, content: {
            if let viewModel {
                SignInForm(viewModel: viewModel) { dismiss() }
            }
        })
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
        // The sheet's gap (18) between the fields, the error and the button, as on Android.
        VStack(alignment: .leading, spacing: TaleedSize.bottomSheetGap) {
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
        .padding(.bottom, TaleedSpacing.s8)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: TaleedSize.bottomSheetGap) {
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
