import SwiftUI

/// Shown while the launch flow runs.
struct SplashView: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s24) {
            Image(taleed: .wordmark)
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 48)
                .accessibilityLabel(l10n.string(.appName))
            ProgressView()
                .tint(TaleedColor.brandPrimary)
                .accessibilityLabel(l10n.string(.commonLoading))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
    }
}

// The launch error and update screens show the brand app bar (wordmark) at the top, then a title and a
// body (the empty/error-state pattern). Suspended follows Android's screen: a large title and an alert.

/// The launch could not finish (no network, server error). The token, if any, is kept.
struct LaunchErrorView: View {
    let error: ApiError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BrandAppBar(showsDivider: true)
            ErrorStateView(error: error, retry: retry)
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
    }
}

/// Blocking: the app is below `minimumVersion.ios`. The button opens the App Store page.
struct UpdateRequiredView: View {
    let storeURL: URL?
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            BrandAppBar(showsDivider: true)
            CenteredStateColumn {
                EmptyState(title: l10n.string(.updateRequiredTitle), message: l10n.string(.updateRequiredBody),
                           icon: .sparkle)
                if let storeURL {
                    TaleedButton(title: l10n.string(.updateRequiredAction), kind: .secondary, size: .large,
                                 isFullWidth: true) {
                        openURL(storeURL)
                    }
                    .padding(.horizontal, TaleedLayout.screenMargin)
                }
            }
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
    }
}

/// The account is suspended: support contacts from `GET /config`, and Sign out. A member with a session
/// (suspended while signed in, or a `banned` sign-in that returned a token) can still open their orders
/// and wallet and delete the account (slice-d.md and slice-e.md, Suspended members): `showsAccountLinks`.
/// Those screens push on the Profile stack, shown here.
struct SuspendedView: View {
    let support: SupportContacts
    var showsAccountLinks = false
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack(path: router.pathBinding(.profile)) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AppRoute.self) { RouteDestinationView(route: $0) }
        }
        .onAppear {
            // Screens opened from here (an order from the orders list) push on the Profile stack.
            router.selectedTab = .profile
        }
    }

    /// As Android's suspended screen (FB-13): no app bar, the large "Account suspended" title, the red
    /// alert with the body, "Contact" with the support rows (as Help), "Still available" with the account
    /// links, then Sign out.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                Text(l10n.string(.suspendedTitle))
                    .taleedFont(TaleedFont.screenTitle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .accessibilityIdentifier("suspended.title")
                InlineAlert(kind: .error, title: l10n.string(.suspendedBody))
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .accessibilityIdentifier("suspended.alert")

                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel(l10n.string(.suspendedContact))
                    SupportContactRows(support: support)
                }

                if showsAccountLinks {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionLabel(l10n.string(.appSuspendedStillAvailable))
                        ListRow(label: l10n.string(.navOrders), leadingIcon: .truck, showsChevron: true) {
                            router.push(.orders)
                        }
                        ListRow(label: l10n.string(.navWallet), leadingIcon: .money, showsChevron: true) {
                            router.push(.wallet)
                        }
                        ListRow(label: l10n.string(.settingsDeleteCta), leadingIcon: .trash, showsChevron: true,
                                showsDivider: false, labelColor: TaleedColor.feedbackError) {
                            router.push(.deleteAccount)
                        }
                    }
                }

                TaleedButton(title: l10n.string(.authSignOut), kind: .tertiary, size: .large, isFullWidth: true) {
                    router.popToRoot(.profile)
                    session.signOut()
                }
                .padding(.horizontal, TaleedLayout.screenMargin)
            }
            .padding(.vertical, TaleedSpacing.s24)
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
    }

    /// A section's eyebrow, as Android's (8 above, 4 below, at the screen margins).
    private func sectionLabel(_ text: String) -> some View {
        Eyebrow(text: text)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.top, TaleedSpacing.s8)
            .padding(.bottom, TaleedSpacing.s4)
    }
}
