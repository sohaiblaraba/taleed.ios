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

/// The launch could not finish (no network, server error). The token, if any, is kept.
struct LaunchErrorView: View {
    let error: ApiError
    let retry: () -> Void

    var body: some View {
        ErrorStateView(error: error, retry: retry)
            .background(TaleedColor.surfacePrimary.ignoresSafeArea())
    }
}

/// Blocking: the app is below `minimumVersion.ios`. The button opens the App Store page.
struct UpdateRequiredView: View {
    let storeURL: URL?
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: TaleedSpacing.s16) {
                Image(taleed: .lettermark)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text(l10n.string(.updateRequiredTitle))
                    .taleedFont(TaleedFont.title2)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(l10n.string(.updateRequiredBody))
                    .taleedFont(TaleedFont.bodyLarge)
                    .foregroundStyle(TaleedColor.textBody)
                    .multilineTextAlignment(.center)
                if let storeURL {
                    TaleedButton(title: l10n.string(.updateRequiredAction), kind: .secondary, size: .large,
                                 isFullWidth: true) {
                        openURL(storeURL)
                    }
                    .padding(.top, TaleedSpacing.s8)
                }
            }
            .padding(TaleedSpacing.s24)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
    }
}

/// The account is suspended: support contacts from `GET /config`, and Sign out. A member suspended while
/// signed in can still open their orders and wallet and delete the account (slice-d.md and slice-e.md,
/// Suspended members): `showsAccountLinks`. Those screens push on the Profile stack, shown here.
struct SuspendedView: View {
    let support: SupportContacts
    var showsAccountLinks = false
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

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

    private var content: some View {
        VStack(spacing: 0) {
            BrandAppBar(showsDivider: true)
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                    InlineAlert(kind: .error, title: l10n.string(.suspendedTitle), message: l10n.string(.suspendedBody))

                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                        Eyebrow(text: l10n.string(.suspendedContact))
                        VStack(spacing: 0) {
                            if let url = URL(string: "mailto:\(support.email)") {
                                contactRow(support.email, icon: .envelope, url: url)
                            }
                            if let url = URL(string: "tel:\(support.phone.filter { !$0.isWhitespace })") {
                                contactRow(support.phone, icon: .phone, url: url, showsDivider: support.whatsappURL != nil)
                            }
                            if let url = support.whatsappURL {
                                contactRow("WhatsApp", icon: .chatCircle, url: url, showsDivider: false)
                            }
                        }
                        .taleedCard()
                        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                    }

                    if showsAccountLinks {
                        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                            Eyebrow(text: l10n.string(.appSuspendedStillAvailable))
                            VStack(spacing: 0) {
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
                            .taleedCard()
                            .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                        }
                    }

                    TaleedButton(title: l10n.string(.authSignOut), kind: .tertiary, size: .large, isFullWidth: true) {
                        router.popToRoot(.profile)
                        session.signOut()
                    }
                }
                .padding(TaleedLayout.screenMargin)
                .padding(.top, TaleedSpacing.s8)
            }
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
    }

    private func contactRow(_ title: String, icon: TaleedIcon, url: URL, showsDivider: Bool = true) -> some View {
        // Emails and phone numbers read left to right in Arabic too.
        ListRow(label: title.isolatedLeftToRight, leadingIcon: icon, showsDivider: showsDivider,
                labelColor: TaleedColor.brandPrimary) {
            openURL(url)
        }
        .accessibilityAddTraits(.isLink)
    }
}
