import SwiftUI

// Full-screen states, the same layout as Android's StateViews: a centred column, padding 24, gap 16.

/// A full-screen loading state: spinner and "Loading…".
struct LoadingStateView: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        CenteredStateColumn {
            ProgressView()
                .controlSize(.large)
                .tint(TaleedColor.brandPrimary)
            Text(l10n.string(.commonLoading))
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textBody)
        }
        .accessibilityElement(children: .combine)
    }
}

/// An error with Retry: warning icon, the app's message for the error, a Tertiary Medium "Retry".
struct ErrorStateView: View {
    let error: ApiError
    let retry: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        CenteredStateColumn {
            TaleedIconView(.warningCircle, size: 32, color: TaleedColor.feedbackError)
                .accessibilityHidden(true)
            Text(l10n.string(error == .network ? .commonErrorNetwork : .commonErrorGeneric))
                .taleedFont(TaleedFont.bodyLarge)
                .foregroundStyle(TaleedColor.textPrimary)
                .multilineTextAlignment(.center)
            TaleedButton(title: l10n.string(.commonRetry), kind: .tertiary, size: .medium, action: retry)
        }
    }
}

/// A short centred text (placeholders, empty lists) with an optional action under it. Android:
/// `MessageState`.
struct MessageStateView<Action: View>: View {
    let text: String
    @ViewBuilder let action: Action

    var body: some View {
        CenteredStateColumn {
            Text(text)
                .taleedFont(TaleedFont.bodyLarge)
                .foregroundStyle(TaleedColor.textBody)
                .multilineTextAlignment(.center)
            action
        }
    }
}

extension MessageStateView where Action == EmptyView {
    init(text: String) {
        self.init(text: text) { EmptyView() }
    }
}

/// "Sign in to continue" with a Secondary Large "Sign in" that hugs its label and opens the sign-in
/// sheet (Android's sign-in placeholder).
struct SignInPromptView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(ShellRouter.self) private var router

    var body: some View {
        MessageStateView(text: l10n.string(.authSignInRequired)) {
            TaleedButton(title: l10n.string(.authSignIn), kind: .secondary, size: .large) {
                router.isSignInPresented = true
            }
        }
    }
}

/// Centres its content in the space (padding 24, gap 16); scrolls when large text makes it taller.
private struct CenteredStateColumn<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: TaleedSpacing.s16) { content }
                    .padding(TaleedSpacing.s24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
