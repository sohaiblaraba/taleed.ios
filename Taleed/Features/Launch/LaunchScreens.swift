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

/// Blocking: the app is below `minimumVersion.ios`.
struct UpdateRequiredView: View {
    let storeURL: URL
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
                TaleedButton(title: l10n.string(.updateRequiredAction), kind: .secondary, size: .large, isFullWidth: true) {
                    openURL(storeURL)
                }
                .padding(.top, TaleedSpacing.s8)
            }
            .padding(TaleedSpacing.s24)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
    }
}

/// The account is suspended: support contacts from `GET /config`, and Sign out.
struct SuspendedView: View {
    let support: SupportContacts
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(\.openURL) private var openURL

    var body: some View {
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

                    TaleedButton(title: l10n.string(.authSignOut), kind: .tertiary, size: .large, isFullWidth: true) {
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
