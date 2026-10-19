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

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.tabProfile))
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                    if let user = session.user {
                        MemberHeader(user: user)
                    } else {
                        TaleedButton(title: l10n.string(.authSignIn), kind: .secondary, size: .large, isFullWidth: true) {
                            router.presentSignIn()
                        }
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.top, TaleedSpacing.s24)
                    }

                    VStack(spacing: 0) {
                        // The member's public profile, as others see it (G5).
                        if let username = session.user?.username {
                            ListRow(label: l10n.string(.navMyProfile), showsChevron: true) {
                                router.push(.member(username: username))
                            }
                            .accessibilityIdentifier("profile.myProfile")
                            ListRow(label: l10n.string(.appProfileMyListings), showsChevron: true) {
                                router.push(.myListings)
                            }
                            .accessibilityIdentifier("profile.myListings")
                            ListRow(label: l10n.string(.navFavorites), showsChevron: true) {
                                router.push(.favorites)
                            }
                            .accessibilityIdentifier("profile.favorites")
                            ListRow(label: l10n.string(.navOrders), showsChevron: true) {
                                router.push(.orders)
                            }
                            .accessibilityIdentifier("profile.orders")
                            ListRow(label: l10n.string(.navWallet),
                                    trailingText: walletHeadline.map { PriceFormatter.format($0, language: l10n.language) },
                                    showsChevron: true) {
                                router.push(.wallet)
                            }
                            .accessibilityIdentifier("profile.wallet")
                        }
                        ListRow(label: l10n.string(.settingsTitle), showsChevron: true) {
                            router.push(.settings)
                        }
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
        .onAppear { Task { await loadWalletHeadline() } }
    }

    /// Quiet: without an answer the row shows no figure.
    private func loadWalletHeadline() async {
        guard session.isSignedIn, let walletApi else {
            walletHeadline = nil
            return
        }
        if let summary = try? await walletApi.wallet(automatic: true) { walletHeadline = summary.headline }
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
                TaleedBadge(title: l10n.string(.profileVerified), tone: .success, icon: .shieldCheck)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TaleedSpacing.s24)
        .padding(.horizontal, TaleedLayout.screenMargin)
    }
}
