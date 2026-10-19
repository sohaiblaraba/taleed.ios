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

/// The two brand faces. Plus Jakarta Sans is the primary face in every language (Latin text, digits
/// and prices); Alexandria is its cascade for Arabic script (design-system §1.3, like the website).
enum TaleedTypeface: CaseIterable, Sendable {
    case plusJakartaSans
    case alexandria

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

    /// The other face, used as the cascade for glyphs this face does not have (Arabic script for
    /// Plus Jakarta Sans).
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

    /// The font at the given content size: Plus Jakarta Sans with Alexandria as cascade by default.
    @MainActor
    func uiFont(_ typeface: TaleedTypeface = .plusJakartaSans, sizeCategory: UIContentSizeCategory = .large) -> UIFont {
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
        let category = UIContentSizeCategory(dynamicTypeSize)
        let font = style.uiFont(sizeCategory: category)
        let scale = font.pointSize / style.size
        content
            .font(Font(font))
            // Arabic is never letter-spaced.
            .tracking(locale.isArabic ? 0 : style.letterSpacing * scale)
            .lineSpacing(style.lineSpacing(.plusJakartaSans, scale: scale))
    }
}

extension Locale {
    /// Arabic app language: no letter spacing (design-system §7).
    var isArabic: Bool { language.languageCode == .arabic }
}

extension View {
    /// Sets a design-system text style: Plus Jakarta Sans with Alexandria for Arabic script, scaled
    /// with Dynamic Type.
    func taleedFont(_ style: TaleedTextStyle) -> some View {
        modifier(TaleedFontModifier(style: style))
    }
}
