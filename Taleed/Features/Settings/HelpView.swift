import SwiftUI

/// "Aide" (screens.md §2 G16 item 11): the support contacts of `GET /config` (the email, the phone and
/// WhatsApp, each shown as text that opens it), the website's pages of `config.links` in the in-app
/// browser, and the app version.
struct HelpView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(LaunchViewModel.self) private var launch
    @Environment(\.appEnvironment) private var environment
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
                    SettingsEyebrow(text: l10n.string(.appSettingsLegal))
                    VStack(spacing: 0) {
                        websiteRow(.footerTerms, page: .terms)
                        websiteRow(.footerPrivacy, page: .privacy)
                        websiteRow(.footerTrust, page: .buyerProtection)
                        websiteRow(.appSettingsGuides, page: .guides)
                    }
                    ListRow(label: l10n.string(.settingsVersion),
                            trailingText: "\(environment.appVersion) (\(environment.buildNumber))".isolatedLeftToRight)
                        .padding(.top, TaleedSpacing.s16)
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
        }
    }

    private func websiteRow(_ title: L10nKey, page: WebsitePage) -> some View {
        ListRow(label: l10n.string(title), showsChevron: true) {
            router.openWebsite(page)
        }
        .accessibilityAddTraits(.isLink)
        .accessibilityIdentifier("help.\(page.rawValue)")
    }
}

/// The email, the phone and WhatsApp of `config.support`: each reads as text and opens Mail, the phone
/// or WhatsApp. WhatsApp shows its number (from `whatsappUrl`) with "WhatsApp" beside it, so a member
/// whose link fails can still read it. Emails and numbers read left to right in Arabic too.
struct SupportContactRows: View {
    let support: SupportContacts
    @Environment(\.openURL) private var openURL
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: 0) {
            if let url = URL(string: "mailto:\(support.email)") {
                row(support.email, icon: .envelope, url: url)
                    .accessibilityIdentifier("support.email")
            }
            if let url = URL(string: "tel:\(support.phone.filter { !$0.isWhitespace })") {
                row(support.phone, icon: .phone, url: url)
                    .accessibilityIdentifier("support.phone")
            }
            if let url = support.whatsappURL {
                whatsappRow(url)
                    .accessibilityIdentifier("support.whatsapp")
            }
        }
    }

    @ViewBuilder
    private func whatsappRow(_ url: URL) -> some View {
        let name = l10n.string(.footerWhatsapp)
        if let number = support.whatsappNumber {
            row(number, icon: .chatCircle, url: url, trailingText: name)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(name), \(number)")
        } else {
            row(name, icon: .chatCircle, url: url)
        }
    }

    private func row(_ title: String, icon: TaleedIcon, url: URL, trailingText: String? = nil) -> some View {
        ListRow(label: title.isolatedLeftToRight, leadingIcon: icon, trailingText: trailingText, labelColor: TaleedColor.brandPrimary) {
            openURL(url)
        }
        .accessibilityAddTraits(.isLink)
    }
}

extension SupportContacts {
    /// The WhatsApp number of `whatsappUrl`, as "+213540693236": the digits of a `wa.me/<number>` path
    /// or of a `phone=` parameter (`api.whatsapp.com/send?phone=…`). Nil when the link carries none.
    var whatsappNumber: String? {
        guard let url = whatsappURL else { return nil }
        let fromPath = url.path.filter(\.isASCIIDigit)
        let fromQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "phone" }?.value?.filter(\.isASCIIDigit) ?? ""
        let digits = fromPath.isEmpty ? fromQuery : fromPath
        return digits.count >= 6 ? "+\(digits)" : nil
    }
}
