import SwiftUI

/// A full-screen loading state.
struct LoadingStateView: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s12) {
            ProgressView()
                .tint(TaleedColor.brandPrimary)
            Text(l10n.string(.commonLoading))
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// An error message with a Retry button.
struct ErrorStateView: View {
    let error: ApiError
    let retry: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ScrollView {
            VStack(spacing: TaleedSpacing.s24) {
                InlineAlert(kind: .error, title: l10n.string(error == .network ? .commonErrorNetwork : .commonErrorGeneric))
                TaleedButton(title: l10n.string(.commonRetry), kind: .secondary, size: .large, isFullWidth: true,
                             action: retry)
            }
            .padding(TaleedLayout.screenMargin)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
    }
}

/// A short centered text, for placeholders and empty states.
struct MessageStateView: View {
    let text: String
    var icon: TaleedIcon = .sparkle

    var body: some View {
        ScrollView {
            EmptyState(title: text, icon: icon)
                .padding(.vertical, TaleedSpacing.s48)
        }
        .defaultScrollAnchor(.center)
    }
}

/// "Sign in to continue" with a button that opens the sign-in sheet.
struct SignInPromptView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(ShellRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: TaleedSpacing.s24) {
                EmptyState(title: l10n.string(.authSignInRequired), icon: .lockKey)
                TaleedButton(title: l10n.string(.authSignIn), kind: .secondary, size: .large, isFullWidth: true) {
                    router.isSignInPresented = true
                }
            }
            .padding(TaleedLayout.screenMargin)
            .padding(.vertical, TaleedSpacing.s24)
        }
        .defaultScrollAnchor(.center)
    }
}
