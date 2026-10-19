import SwiftUI

struct ProfileView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(ShellRouter.self) private var router

    var body: some View {
        ShellScreen {
            ShellBrandAppBar()
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeading(title: l10n.string(.tabProfile), showsDivider: false)
                    VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                        if let user = session.user {
                            ProfileHeader(user: user)
                        } else {
                            TaleedButton(title: l10n.string(.authSignIn), kind: .secondary, size: .large, isFullWidth: true) {
                                router.isSignInPresented = true
                            }
                        }

                        TaleedListRow(title: l10n.string(.settingsTitle), showsDivider: false) {
                            router.profilePath.append(.settings)
                        }
                        .taleedCard()
                        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))

                        if session.isSignedIn {
                            TaleedButton(title: l10n.string(.authSignOut), kind: .tertiary, size: .large, isFullWidth: true) {
                                session.signOut()
                            }
                        }
                    }
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.bottom, TaleedSpacing.s24)
                }
            }
        }
    }
}

/// Avatar, `displayName`, `@username` when it differs, and the badge.
private struct ProfileHeader: View {
    let user: User
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(spacing: TaleedSpacing.s16) {
            TaleedAvatar(
                initials: TaleedAvatar.initials(from: user.username ?? user.displayName),
                size: 72,
                imageURL: user.avatarURL,
                isVerified: user.isVerified || user.isOfficial
            )
            .accessibilityHidden(false)
            .accessibilityLabel(l10n.string(.profileAvatar))
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Text(verbatim: user.displayName.isolatedByContent)
                    .taleedFont(TaleedFont.title2)
                    .foregroundStyle(TaleedColor.textPrimary)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TaleedSpacing.s16)
        .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous))
    }
}
