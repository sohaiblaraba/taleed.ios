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
                        websiteRow(.footerTerms, icon: .fileText, page: .terms)
                        websiteRow(.footerPrivacy, icon: .lock, page: .privacy)
                    }
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
        }
    }

    private func websiteRow(_ title: L10nKey, icon: TaleedIcon, page: WebsitePage) -> some View {
        ListRow(label: l10n.string(title), leadingIcon: icon, showsChevron: true) {
            router.openWebsite(page)
        }
        .accessibilityAddTraits(.isLink)
        .accessibilityIdentifier("help.\(page.rawValue)")
    }
}

/// The email, the phone and WhatsApp of `config.support`, as Android's rows: the email and the phone
/// read as text on one line (left to right in Arabic too; the phone in digit groups), "WhatsApp" for
/// the link; each opens Mail, the phone or WhatsApp, so it ends with the arrow out, not a chevron.
struct SupportContactRows: View {
    let support: SupportContacts
    @Environment(\.openURL) private var openURL
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: 0) {
            if let url = URL(string: "mailto:\(support.email)") {
                row(support.email.isolatedLeftToRight, icon: .envelope, url: url, oneLine: true)
                    .accessibilityIdentifier("support.email")
            }
            if let url = URL(string: "tel:\(support.phone.filter { !$0.isWhitespace })") {
                row(SupportPhone.grouped(support.phone).isolatedLeftToRight, icon: .phone, url: url, oneLine: true)
                    .accessibilityIdentifier("support.phone")
            }
            if let url = support.whatsappURL {
                row(l10n.string(.footerWhatsapp), icon: .chatCircle, url: url)
                    .accessibilityIdentifier("support.whatsapp")
            }
        }
    }

    private func row(_ title: String, icon: TaleedIcon, url: URL, oneLine: Bool = false) -> some View {
        ListRow(label: title, leadingIcon: icon, opensOutside: true, keepsLabelOnOneLine: oneLine) {
            openURL(url)
        }
        .accessibilityAddTraits(.isLink)
    }
}

/// The support phone as people read it: an Algerian number in groups ("+213 540 69 32 36",
/// "0540 69 32 36"); anything else as the API sent it.
enum SupportPhone {
    static func grouped(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        if phone.hasPrefix("+213"), digits.count == 12 {
            let local = Array(digits.dropFirst(3))
            return "+213 " + groups(local, sizes: [3, 2, 2, 2])
        }
        if digits.count == 10, digits.hasPrefix("0"), phone.allSatisfy({ $0.isNumber || $0 == " " }) {
            return groups(Array(digits), sizes: [4, 2, 2, 2])
        }
        return phone
    }

    private static func groups(_ characters: [Character], sizes: [Int]) -> String {
        var parts: [String] = []
        var index = 0
        for size in sizes {
            parts.append(String(characters[index..<index + size]))
            index += size
        }
        return parts.joined(separator: " ")
    }
}
