import Foundation
import NukeUI
import SwiftUI

/// A block of an official announcement's HTML (slice C: `html` is sanitized HTML, "paragraphs,
/// headings, lists, links and images"; the website's allow-list is in `src/lib/chat-html.ts`).
enum AnnouncementBlock: Equatable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    /// A list item: "•" or "3." and its nesting depth (0 at the top).
    case listItem(marker: String, depth: Int, AttributedString)
    case quote(AttributedString)
    case image(URL)
    case rule
}

/// Turns the announcement's sanitized HTML into blocks the bubble draws natively (no web view):
/// `h2`–`h4`, `p`, `div`, `br`, `strong`/`b`, `em`/`i`, `u`, `s`, `ul`/`ol`/`li`, `a`, `img`,
/// `blockquote`, `hr`, `span`. Other tags keep their text. Relative links and images resolve against
/// the website (`GET /config` `links.website`).
enum AnnouncementHTML {
    static func blocks(from html: String, baseURL: URL?) -> [AnnouncementBlock] {
        var builder = Builder(baseURL: baseURL)
        var index = html.startIndex
        while index < html.endIndex {
            guard let open = html[index...].firstIndex(of: "<") else {
                builder.text(String(html[index...]))
                break
            }
            if open > index { builder.text(String(html[index..<open])) }
            guard let close = html[open...].firstIndex(of: ">") else {
                builder.text(String(html[open...]))
                break
            }
            builder.tag(String(html[html.index(after: open)..<close]))
            index = html.index(after: close)
        }
        builder.flush()
        return builder.blocks
    }

    /// Decodes the character references the sanitizer leaves (`&amp;`, `&nbsp;`, `&#39;`, `&#x2019;`…).
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let end = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let name = String(text[text.index(after: index)..<end])
            if let decoded = entity(name) {
                result.append(decoded)
                index = text.index(after: end)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "laquo": "«", "raquo": "»", "rsquo": "’", "lsquo": "‘", "hellip": "…", "mdash": "—", "ndash": "–",
    ]

    private static func entity(_ name: String) -> String? {
        if let value = named[name] { return value }
        guard name.hasPrefix("#") else { return nil }
        let number = name.dropFirst()
        let value = number.lowercased().hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
        return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }

    /// The value of an attribute in a tag's text (`href="/listings/1"`).
    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 2...4 {
            if let range = Range(match.range(at: group), in: tag) { return decodeEntities(String(tag[range])) }
        }
        return nil
    }

    /// A link or image address: absolute http(s), or a website path.
    static func resolve(_ link: String?, baseURL: URL?) -> URL? {
        guard let link = link?.trimmingCharacters(in: .whitespaces), !link.isEmpty else { return nil }
        if link.lowercased().hasPrefix("http://") || link.lowercased().hasPrefix("https://") { return URL(string: link) }
        guard link.hasPrefix("/"), !link.hasPrefix("//") else { return nil }
        if let baseURL, let url = URL(string: link, relativeTo: baseURL) { return url.absoluteURL }
        return URL(string: link)
    }

    private struct Builder {
        let baseURL: URL?
        var blocks: [AnnouncementBlock] = []
        private var current = AttributedString()
        private var bold = 0
        private var italic = 0
        private var underline = 0
        private var strike = 0
        private var links: [URL?] = []
        private var headingLevel: Int?
        private var quoteDepth = 0
        /// One entry per open list: ordered lists count their items.
        private var lists: [(ordered: Bool, count: Int)] = []
        private var itemMarker: (marker: String, depth: Int)?

        init(baseURL: URL?) {
            self.baseURL = baseURL
        }

        mutating func text(_ raw: String) {
            // HTML collapses runs of white space; a line break only comes from `<br>` or a block.
            let collapsed = AnnouncementHTML.decodeEntities(raw)
                .replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ", options: .regularExpression)
            var piece = collapsed
            if current.characters.isEmpty || current.characters.last == "\n" {
                piece = String(piece.drop { $0 == " " })
            } else if current.characters.last == " ", piece.hasPrefix(" ") {
                piece.removeFirst()
            }
            guard !piece.isEmpty else { return }
            var run = AttributedString(piece)
            var intent: InlinePresentationIntent = []
            if bold > 0 || headingLevel != nil { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if strike > 0 { intent.insert(.strikethrough) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }
            if let link = links.compactMap({ $0 }).last {
                run.link = link
                run.underlineStyle = .single
            } else if underline > 0 {
                run.underlineStyle = .single
            }
            current.append(run)
        }

        mutating func tag(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix("!") else { return }
            let isClosing = trimmed.hasPrefix("/")
            let body = isClosing ? String(trimmed.dropFirst()) : trimmed
            let name = String(body.prefix { $0.isLetter || $0.isNumber }).lowercased()
            if isClosing { close(name) } else { open(name, tag: body) }
        }

        // One case per tag of the allow-list.
        // swiftlint:disable:next cyclomatic_complexity
        private mutating func open(_ name: String, tag: String) {
            switch name {
            case "strong", "b": bold += 1
            case "em", "i": italic += 1
            case "u": underline += 1
            case "s", "strike", "del": strike += 1
            case "a": links.append(AnnouncementHTML.resolve(AnnouncementHTML.attribute("href", in: tag), baseURL: baseURL))
            case "br": current.append(AttributedString("\n"))
            case "p", "div": flush()
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flush()
                headingLevel = Int(name.dropFirst()) ?? 2
            case "blockquote":
                flush()
                quoteDepth += 1
            case "ul", "ol":
                flush()
                lists.append((ordered: name == "ol", count: 0))
            case "li":
                flush()
                if lists.isEmpty { lists.append((ordered: false, count: 0)) }
                lists[lists.count - 1].count += 1
                let list = lists[lists.count - 1]
                itemMarker = (list.ordered ? "\(list.count)." : "•", lists.count - 1)
            case "hr":
                flush()
                blocks.append(.rule)
            case "img":
                flush()
                if let url = AnnouncementHTML.resolve(AnnouncementHTML.attribute("src", in: tag), baseURL: baseURL) {
                    blocks.append(.image(url))
                }
            default:
                break
            }
        }

        // swiftlint:disable:next cyclomatic_complexity
        private mutating func close(_ name: String) {
            switch name {
            case "strong", "b": bold = max(0, bold - 1)
            case "em", "i": italic = max(0, italic - 1)
            case "u": underline = max(0, underline - 1)
            case "s", "strike", "del": strike = max(0, strike - 1)
            case "a": if !links.isEmpty { links.removeLast() }
            case "p", "div", "li": flush()
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flush()
                headingLevel = nil
            case "blockquote":
                flush()
                quoteDepth = max(0, quoteDepth - 1)
            case "ul", "ol":
                flush()
                if !lists.isEmpty { lists.removeLast() }
            default:
                break
            }
        }

        /// Ends the paragraph in progress as a block of the kind the open tags say.
        mutating func flush() {
            var text = current
            current = AttributedString()
            while let last = text.characters.last, last == " " || last == "\n" {
                text.characters.removeLast()
            }
            guard !text.characters.isEmpty else { return }
            if let level = headingLevel {
                blocks.append(.heading(level: level, text))
            } else if let item = itemMarker {
                blocks.append(.listItem(marker: item.marker, depth: item.depth, text))
                itemMarker = nil
            } else if quoteDepth > 0 {
                blocks.append(.quote(text))
            } else {
                blocks.append(.paragraph(text))
            }
        }
    }
}

/// An official announcement in its bubble: the blocks of `html`, in the bubble's text colour, with
/// links that open through `openURL` (the screen routes them).
struct AnnouncementView: View {
    let blocks: [AnnouncementBlock]
    var color: Color = TaleedColor.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .tint(TaleedColor.brandPrimary)
    }

    @ViewBuilder
    private func view(for block: AnnouncementBlock) -> some View {
        switch block {
        case let .paragraph(text):
            Text(text).taleedFont(TaleedFont.bodyLarge).foregroundStyle(color)
        case let .heading(level, text):
            Text(text)
                .taleedFont(level <= 2 ? TaleedFont.headline : TaleedFont.sectionTitle)
                .foregroundStyle(color)
                .accessibilityAddTraits(.isHeader)
        case let .listItem(marker, depth, text):
            HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8) {
                Text(verbatim: marker).taleedFont(TaleedFont.bodyLarge).foregroundStyle(color)
                Text(text).taleedFont(TaleedFont.bodyLarge).foregroundStyle(color)
            }
            .padding(.leading, CGFloat(depth) * TaleedSpacing.s16)
        case let .quote(text):
            Text(text)
                .taleedFont(TaleedFont.bodyLarge)
                .italic()
                .foregroundStyle(TaleedColor.textBody)
                .padding(.leading, TaleedSpacing.s12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(TaleedColor.borderSubtle).frame(width: 3)
                }
        case let .image(url):
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                } else {
                    Rectangle().fill(TaleedColor.skeleton).frame(height: 140)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous))
            .accessibilityHidden(true)
        case .rule:
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).accessibilityHidden(true)
        }
    }
}
