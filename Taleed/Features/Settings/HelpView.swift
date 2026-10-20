import SwiftUI

/// "Aide" (screens.md §2 G16 item 11), as Android's Help: "Contact" with the support contacts of
/// `GET /config` (the email, the phone and WhatsApp, each opening it), then "Aide" with the website's
/// pages of `config.links` in the in-app browser. The app version lives in Settings.
struct HelpView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(LaunchViewModel.self) private var launch
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.footerHelp), onBack: { dismiss() })
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let support = launch.config?.support {
                        SettingsEyebrow(text: l10n.string(.footerContact))
                        SupportContactRows(support: support)
                    }
                    SettingsEyebrow(text: l10n.string(.footerHelp))
                    VStack(spacing: 0) {
                        websiteRow(.footerTrust, icon: .shieldCheck, page: .buyerProtection)
                        websiteRow(.guidesHeading, icon: .info, page: .guides)
                        websiteRow(.footerTerms, page: .terms)
                        websiteRow(.footerPrivacy, page: .privacy)
                    }
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
        }
    }

    private func websiteRow(_ title: L10nKey, icon: TaleedIcon? = nil, page: WebsitePage) -> some View {
        ListRow(label: l10n.string(title), leadingIcon: icon, showsChevron: true) {
            router.openWebsite(page)
        }
        .accessibilityAddTraits(.isLink)
        .accessibilityIdentifier("help.\(page.rawValue)")
    }
}

/// The email, the phone and WhatsApp of `config.support`, as Android's rows: the email and the phone
/// read as text (left to right in Arabic too), "WhatsApp" for the link; each opens Mail, the phone or
/// WhatsApp.
struct SupportContactRows: View {
    let support: SupportContacts
    @Environment(\.openURL) private var openURL
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: 0) {
            if let url = URL(string: "mailto:\(support.email)") {
                row(support.email.isolatedLeftToRight, icon: .envelope, url: url)
                    .accessibilityIdentifier("support.email")
            }
            if let url = URL(string: "tel:\(support.phone.filter { !$0.isWhitespace })") {
                row(support.phone.isolatedLeftToRight, icon: .phone, url: url)
                    .accessibilityIdentifier("support.phone")
            }
            if let url = support.whatsappURL {
                row(l10n.string(.footerWhatsapp), icon: .chatCircle, url: url)
                    .accessibilityIdentifier("support.whatsapp")
            }
        }
    }

    private func row(_ title: String, icon: TaleedIcon, url: URL) -> some View {
        ListRow(label: title, leadingIcon: icon, showsChevron: true) {
            openURL(url)
        }
        .accessibilityAddTraits(.isLink)
    }
}
