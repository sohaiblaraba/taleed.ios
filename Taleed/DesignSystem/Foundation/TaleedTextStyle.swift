import SwiftUI
import UIKit

/// Font weights of the bundled faces (static files, one per weight).
enum TaleedFontWeight: Int, CaseIterable, Sendable {
    case regular = 400
    case medium = 500
    case semibold = 600
    case bold = 700
    case extrabold = 800

    fileprivate var fileSuffix: String {
        switch self {
        case .regular: "Regular"
        case .medium: "Medium"
        case .semibold: "SemiBold"
        case .bold: "Bold"
        case .extrabold: "ExtraBold"
        }
    }
}

/// The two brand faces: Plus Jakarta Sans for Latin, Alexandria for Arabic.
enum TaleedTypeface: CaseIterable, Sendable {
    case plusJakartaSans
    case alexandria

    /// Alexandria for every text style when the app language is Arabic.
    init(locale: Locale) {
        self = locale.language.languageCode == .arabic ? .alexandria : .plusJakartaSans
    }

    var familyPrefix: String {
        switch self {
        case .plusJakartaSans: "PlusJakartaSans"
        case .alexandria: "Alexandria"
        }
    }

    /// Natural line height over font size (hhea ascender + descender over units per em).
    var naturalLineHeight: CGFloat {
        switch self {
        case .plusJakartaSans: 1.26
        case .alexandria: 1.219
        }
    }

    /// The other face, used as the cascade for glyphs this face does not have (Arabic in Latin text,
    /// Latin in Arabic text).
    var fallback: TaleedTypeface { self == .alexandria ? .plusJakartaSans : .alexandria }

    func postScriptName(_ weight: TaleedFontWeight) -> String { "\(familyPrefix)-\(weight.fileSuffix)" }
}

/// A text style token: size, weight, line height and letter spacing, from tokens.json.
struct TaleedTextStyle: Hashable, Sendable {
    let size: CGFloat
    let weight: TaleedFontWeight
    /// Line height in points. Nil means the font's natural line height (Figma "AUTO").
    let lineHeight: CGFloat?
    /// Letter spacing in points. Never applied to Arabic.
    let letterSpacing: CGFloat
    /// The Dynamic Type style this token scales with.
    let relativeTo: Font.TextStyle

    func with(weight: TaleedFontWeight) -> TaleedTextStyle {
        TaleedTextStyle(size: size, weight: weight, lineHeight: lineHeight, letterSpacing: letterSpacing, relativeTo: relativeTo)
    }

    /// The font at the given content size, with the other brand face as cascade.
    @MainActor
    func uiFont(_ typeface: TaleedTypeface, sizeCategory: UIContentSizeCategory = .large) -> UIFont {
        TaleedFontCache.font(style: self, typeface: typeface, sizeCategory: sizeCategory)
    }

    /// Extra spacing between lines so multi-line text reaches the token's line height.
    /// SwiftUI cannot tighten lines, so tokens below the natural height (120 % styles) keep the natural one.
    func lineSpacing(_ typeface: TaleedTypeface, scale: CGFloat) -> CGFloat {
        guard let lineHeight else { return 0 }
        return max(0, (lineHeight - size * typeface.naturalLineHeight) * scale)
    }
}

@MainActor
private enum TaleedFontCache {
    private struct Key: Hashable {
        let style: TaleedTextStyle
        let typeface: TaleedTypeface
        let sizeCategory: UIContentSizeCategory
    }

    private static var fonts: [Key: UIFont] = [:]

    static func font(style: TaleedTextStyle, typeface: TaleedTypeface, sizeCategory: UIContentSizeCategory) -> UIFont {
        let key = Key(style: style, typeface: typeface, sizeCategory: sizeCategory)
        if let font = fonts[key] { return font }
        let cascade = UIFontDescriptor(fontAttributes: [.name: typeface.fallback.postScriptName(style.weight)])
        let descriptor = UIFontDescriptor(fontAttributes: [.name: typeface.postScriptName(style.weight)])
            .addingAttributes([.cascadeList: [cascade]])
        let base = UIFont(descriptor: descriptor, size: style.size)
        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory)
        let font = UIFontMetrics(forTextStyle: style.relativeTo.uiTextStyle).scaledFont(for: base, compatibleWith: traits)
        fonts[key] = font
        return font
    }
}

extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

private struct TaleedFontModifier: ViewModifier {
    let style: TaleedTextStyle
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let typeface = TaleedTypeface(locale: locale)
        let category = UIContentSizeCategory(dynamicTypeSize)
        let font = style.uiFont(typeface, sizeCategory: category)
        let scale = font.pointSize / style.size
        content
            .font(Font(font))
            // Arabic is never letter-spaced.
            .tracking(typeface == .alexandria ? 0 : style.letterSpacing * scale)
            .lineSpacing(style.lineSpacing(typeface, scale: scale))
    }
}

extension View {
    /// Sets a design-system text style. Scales with Dynamic Type and uses Alexandria in Arabic.
    func taleedFont(_ style: TaleedTextStyle) -> some View {
        modifier(TaleedFontModifier(style: style))
    }
}
