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

/// An error with Retry, in the empty-state layout (design-system §3.5) so both states read as one
/// pattern: `warningCircle` in the 84 pt `errorSoft` circle, a title ("No connection" offline), the
/// app's message for the error (rate limit, server…) and an Outline Medium "Retry". A `404 not_found`
/// shows the "no longer available" state instead, with "Back to home" (screens that live in a stack
/// may pass `onBack` to go back instead).
struct ErrorStateView: View {
    let error: ApiError
    let retry: () -> Void
    var onBack: (() -> Void)?
    /// True draws the state where the caller places it (at its empty state's position) instead of
    /// centred in the space.
    var isInline = false
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router: AppRouter?

    var body: some View {
        if error.isNotFound {
            NotFoundStateView(onBack: onBack ?? router.map { router in { router.open(.home) } })
        } else if isInline {
            state
        } else {
            CenteredStateColumn { state }
        }
    }

    private var state: some View {
        EmptyState(title: l10n.string(Self.titleKey(for: error)), message: message, actionTitle: l10n.string(.commonRetry),
                   action: retry, icon: .warningCircle, iconTone: .error)
    }

    private var message: String? { Self.message(for: error, l10n: l10n) }

    /// "Check your network…" offline; otherwise the error's own message, none when it is the generic one
    /// (the title already says it).
    static func message(for error: ApiError, l10n: LanguageManager) -> String? {
        if error == .network { return l10n.string(.appErrorOfflineBody) }
        return error.messageKey == .commonErrorGeneric ? nil : l10n.message(for: error)
    }

    /// "No connection" offline, "Something went wrong" otherwise.
    static func titleKey(for error: ApiError) -> L10nKey {
        error == .network ? .appErrorOfflineTitle : .appErrorTitle
    }
}

/// "This is no longer available" (`404 not_found`): a removed or hidden listing, a suspended member,
/// an order that is not the member's.
struct NotFoundStateView: View {
    /// A screen's own wording ("Cet article n'est plus disponible."); the generic title otherwise.
    var title: String?
    var onBack: (() -> Void)?
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        CenteredStateColumn {
            TaleedIconView(.magnifyingGlass, size: 32, color: TaleedColor.textSecondary)
                .accessibilityHidden(true)
            VStack(spacing: TaleedSpacing.s8) {
                Text(title ?? l10n.string(.appNotFoundTitle))
                    .taleedFont(TaleedFont.title2)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(l10n.string(.appNotFoundBody))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            if let onBack {
                TaleedButton(title: l10n.string(.commonGoHome), kind: .tertiary, size: .medium, action: onBack)
            }
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
/// sheet (Android's sign-in placeholder). With an icon and a title: the empty-state layout (84 pt
/// circle on `brandSoft`, title, the same body), as the app's other prompt states.
struct SignInPromptView: View {
    var icon: TaleedIcon?
    var title: String?
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let icon, let title {
            CenteredStateColumn {
                EmptyState(title: title, message: l10n.string(.authSignInRequired), icon: icon)
                signInButton
            }
            .accessibilityIdentifier("signInPrompt")
        } else {
            MessageStateView(text: l10n.string(.authSignInRequired)) { signInButton }
        }
    }

    private var signInButton: some View {
        TaleedButton(title: l10n.string(.authSignIn), kind: .secondary, size: .large) {
            router.presentSignIn()
        }
    }
}

/// Centres its content in the space (padding 24, gap 16); scrolls when large text makes it taller.
struct CenteredStateColumn<Content: View>: View {
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
