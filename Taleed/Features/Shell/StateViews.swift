import SwiftUI

/// A full-screen loading state.
struct LoadingStateView: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(l10n.string(.commonLoading))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An error message with a Retry button.
struct ErrorStateView: View {
    let error: ApiError
    let retry: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: 16) {
            Text(l10n.string(error == .network ? .commonErrorNetwork : .commonErrorGeneric))
                .multilineTextAlignment(.center)
            Button(l10n.string(.commonRetry), action: retry)
                .buttonStyle(.borderedProminent)
                .frame(minHeight: Theme.minTouchTarget)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A short centered text, for placeholders and empty states.
struct MessageStateView: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Sign in to continue" with a button that opens the sign-in sheet.
struct SignInPromptView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(ShellRouter.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            Text(l10n.string(.authSignInRequired))
                .multilineTextAlignment(.center)
            Button(l10n.string(.authSignIn)) { router.isSignInPresented = true }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: Theme.minTouchTarget)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
