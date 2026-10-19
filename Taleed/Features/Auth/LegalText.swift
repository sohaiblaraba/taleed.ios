import SwiftUI

/// A sentence with `<terms>…</terms>` and `<privacy>…</privacy>` parts, as the website's rich
/// messages write them (`auth.termsConsent`). The tagged parts are links that open the website's
/// terms and privacy pages (`GET /config` `links`) in the in-app browser.
struct LegalText: View {
    let text: String
    var style: TaleedTextStyle = TaleedFont.caption
    var color: Color = TaleedColor.textBody
    var linkColor: Color = TaleedColor.textPrimary
    @Environment(AppRouter.self) private var router

    var body: some View {
        Text(Self.attributed(text, linkColor: linkColor))
            .taleedFont(style)
            .foregroundStyle(color)
            .tint(linkColor)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard let page = Self.page(of: url) else { return .discarded }
                router.openWebsite(page)
                return .handled
            })
    }

    /// The tags the text may hold, and the page each one opens.
    static let tags: [(name: String, page: WebsitePage)] = [("terms", .terms), ("privacy", .privacy)]
    private static let linkScheme = "taleed-website"

    /// The text without its tags, the tagged parts underlined links.
    static func attributed(_ text: String, linkColor: Color) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(text)
        while let (tag, open) = firstTag(in: rest) {
            result += AttributedString(String(rest[..<open.lowerBound]))
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: "</\(tag.name)>") else {
                rest = afterOpen
                continue
            }
            var link = AttributedString(String(afterOpen[..<close.lowerBound]))
            link.link = URL(string: "\(linkScheme)://\(tag.page.rawValue)")
            link.underlineStyle = .single
            link.foregroundColor = linkColor
            result += link
            rest = afterOpen[close.upperBound...]
        }
        result += AttributedString(String(rest))
        return result
    }

    /// The plain text, tags removed (for tests and accessibility).
    static func plain(_ text: String) -> String {
        String(attributed(text, linkColor: .clear).characters)
    }

    static func page(of url: URL) -> WebsitePage? {
        guard url.scheme == linkScheme, let host = url.host() else { return nil }
        return WebsitePage(rawValue: host)
    }

    private static func firstTag(in text: Substring) -> ((name: String, page: WebsitePage), Range<Substring.Index>)? {
        tags.compactMap { tag in text.range(of: "<\(tag.name)>").map { (tag, $0) } }
            .min { $0.1.lowerBound < $1.1.lowerBound }
    }
}
