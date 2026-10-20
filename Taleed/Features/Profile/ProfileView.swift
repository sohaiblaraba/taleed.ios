import SwiftUI

/// Profile (decision D-12, Figma does not draw it), the same layout as Android's ProfileScreen: the
/// centred-title top app bar, the member header or "Sign in", a flat Settings row and "Sign out".
struct ProfileView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.walletApi) private var walletApi
    /// The website menu's figure next to "Portefeuille": `balance + voucherBalance` of `GET /wallet`
    /// (`GET /me` does not carry it).
    @State private var walletHeadline: Int?
    /// The first wallet answer (or its failure) came back: until then the row holds a placeholder
    /// where the figure goes, so it does not pop in after the first paint.
    @State private var walletLoaded = false
    @Environment(\.referralsApi) private var referralsApi
    /// What each side of a referral can earn (`program` of `GET /me/referrals`), for the website menu's
    /// "Gagnez 1 500 DA en parrainant"; "Parrainage" until it is known (screens.md §7 G18).
    @State private var referralTotal: Int?

    private var unreadNotifications: Int { session.user?.unreadNotifications ?? 0 }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.tabProfile))
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                    if let user = session.user {
                        MemberHeader(user: user)
                    } else {
                        // Signed out: the sign-in sheet's subtitle says what the button is for.
                        VStack(spacing: TaleedSpacing.s16) {
                            Text(l10n.string(.authLoginSubtitle))
                                .taleedFont(TaleedFont.bodyRegular)
                                .foregroundStyle(TaleedColor.textBody)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .fixedSize(horizontal: false, vertical: true)
                            TaleedButton(title: l10n.string(.authSignIn), kind: .secondary, size: .large, isFullWidth: true) {
                                router.presentSignIn()
                            }
                        }
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.top, TaleedSpacing.s24)
                    }

                    VStack(spacing: 0) {
                        // The member's public profile, as others see it (G5).
                        // Android's hub order and icons (the website menu puts Orders and Wallet before
                        // Favorites); the icons are the ones of the Settings rows' family.
                        if let username = session.user?.username {
                            ListRow(label: l10n.string(.navMyProfile), leadingIcon: .user, showsChevron: true) {
                                router.push(.member(username: username))
                            }
                            .accessibilityIdentifier("profile.myProfile")
                            ListRow(label: l10n.string(.appProfileMyListings), leadingIcon: .storefront, showsChevron: true) {
                                router.push(.myListings)
                            }
                            .accessibilityIdentifier("profile.myListings")
                            ListRow(label: l10n.string(.navOrders), leadingIcon: .truck, showsChevron: true) {
                                router.push(.orders)
                            }
                            .accessibilityIdentifier("profile.orders")
                            ListRow(label: l10n.string(.navWallet), leadingIcon: .money,
                                    trailingText: walletHeadline.map { PriceFormatter.format($0, language: l10n.language) },
                                    isTrailingLoading: walletHeadline == nil && !walletLoaded, showsChevron: true) {
                                router.push(.wallet)
                            }
                            .accessibilityIdentifier("profile.wallet")
                            // The bell's count (`counts.unreadNotifications`).
                            ListRow(label: l10n.string(.navNotifications), leadingIcon: .bell, badgeCount: unreadNotifications,
                                    badgeAccessibilityLabel: l10n.format(.appBadgeUnreadNotifications, unreadNotifications),
                                    showsChevron: true) {
                                router.push(.notifications)
                            }
                            .accessibilityIdentifier("profile.notifications")
                            ListRow(label: l10n.string(.navFavorites), leadingIcon: .heart, showsChevron: true) {
                                router.push(.favorites)
                            }
                            .accessibilityIdentifier("profile.favorites")
                            ListRow(label: referralsLabel, leadingIcon: .gift, showsChevron: true) {
                                router.push(.referrals)
                            }
                            // "Parrainage" fades into "Gagnez 1 500 DA en parrainant" rather than swapping.
                            .animation(.easeInOut(duration: TaleedMotion.transitionMin), value: referralTotal)
                            .accessibilityIdentifier("profile.referrals")
                        }
                        ListRow(label: l10n.string(.settingsTitle), leadingIcon: .slidersHorizontal, showsChevron: true) {
                            router.push(.settings)
                        }
                        .accessibilityIdentifier("profile.settings")
                        ListRow(label: l10n.string(.footerHelp), leadingIcon: .info, showsChevron: true) {
                            router.push(.help)
                        }
                        .accessibilityIdentifier("profile.help")
                    }

                    if session.isSignedIn {
                        TaleedButton(title: l10n.string(.authSignOut), kind: .tertiary, size: .large, isFullWidth: true) {
                            session.signOut()
                        }
                        .padding(.horizontal, TaleedLayout.screenMargin)
                    }
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
        }
        // Again each time the hub shows (back from the wallet, a checkout, an order) and after sign-in.
        .task(id: session.user?.id) { await loadWalletHeadline() }
        .task(id: session.user?.id) { await loadReferralTotal() }
        .onAppear { Task { await loadWalletHeadline() } }
    }

    private var referralsLabel: String {
        guard let referralTotal, referralTotal > 0 else { return l10n.string(.referralsTitle) }
        return l10n.format(.appReferralsEyebrow, PriceFormatter.format(referralTotal, language: l10n.language))
    }

    /// Quiet, once per member: without an answer the row reads "Parrainage".
    private func loadReferralTotal() async {
        guard session.isSignedIn, let referralsApi else {
            referralTotal = nil
            return
        }
        if let page = try? await referralsApi.referrals(cursor: nil, automatic: true) { referralTotal = page.program.totalPerSide }
    }

    /// Quiet: without an answer the row shows no figure.
    private func loadWalletHeadline() async {
        guard session.isSignedIn, let walletApi else {
            walletHeadline = nil
            walletLoaded = false
            return
        }
        if let summary = try? await walletApi.wallet(automatic: true) { walletHeadline = summary.headline }
        walletLoaded = true
    }
}

/// Avatar 72, `displayName`, `@username` when it differs, and the badge, centred.
private struct MemberHeader: View {
    let user: User
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s8) {
            TaleedAvatar(
                initials: TaleedAvatar.initials(from: user.displayName),
                size: TaleedSize.avatarXxxl,
                imageURL: user.avatarURL
            )
            .accessibilityHidden(false)
            .accessibilityLabel(l10n.string(.profileAvatar))
            Text(verbatim: user.displayName.isolatedByContent)
                .taleedFont(TaleedFont.title2)
                .foregroundStyle(TaleedColor.textPrimary)
                .multilineTextAlignment(.center)
            if let handle = user.handle, handle != user.displayName {
                Text(verbatim: handle.isolatedLeftToRight)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondary)
            }
            if user.isOfficial {
                TaleedBadge(title: l10n.string(.profileOfficial), tone: .brand, icon: .sealCheck)
            } else if user.isVerified {
                TaleedBadge.verified(l10n.string(.profileVerified))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TaleedSpacing.s24)
        .padding(.horizontal, TaleedLayout.screenMargin)
    }
}
