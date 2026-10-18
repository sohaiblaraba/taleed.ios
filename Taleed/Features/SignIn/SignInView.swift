import SwiftUI

/// Opened as a sheet from every "Sign in" button.
struct SignInView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SignInViewModel?

    var body: some View {
        NavigationStack {
            if let viewModel {
                SignInForm(viewModel: viewModel) { dismiss() }
                    .navigationTitle(l10n.string(.authSignIn))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .frame(minWidth: Theme.minTouchTarget, minHeight: Theme.minTouchTarget)
                            }
                            .accessibilityLabel(l10n.string(.commonClose))
                        }
                    }
            }
        }
        .onAppear {
            if viewModel == nil { viewModel = SignInViewModel(session: session) }
        }
    }
}

private struct SignInForm: View {
    @Bindable var viewModel: SignInViewModel
    let onDone: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        Form {
            Section {
                TextField(l10n.string(.authEmail), text: $viewModel.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .frame(minHeight: Theme.minTouchTarget)
                SecureField(l10n.string(.authPassword), text: $viewModel.password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .frame(minHeight: Theme.minTouchTarget)
            }

            if let errorKey = viewModel.errorKey {
                Section {
                    Text(l10n.string(errorKey))
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                                .accessibilityLabel(l10n.string(.commonLoading))
                        } else {
                            Text(l10n.string(.authSignIn))
                        }
                        Spacer()
                    }
                    .frame(minHeight: Theme.minTouchTarget)
                }
                .disabled(!viewModel.canSubmit)
            }
        }
        .disabled(viewModel.isLoading)
    }

    private func submit() {
        Task {
            if await viewModel.submit() { onDone() }
        }
    }
}
