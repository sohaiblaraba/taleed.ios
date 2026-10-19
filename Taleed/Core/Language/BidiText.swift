import SwiftUI

extension String {
    /// Keeps a left-to-right run, such as `@amina` or an email address, in order inside
    /// right-to-left text (Unicode LRI ... PDI). Without it, Arabic shows `amina@`.
    var isolatedLeftToRight: String { "\u{2066}\(self)\u{2069}" }

    /// Gives text written by members the direction of its own first strong letter
    /// (Unicode FSI ... PDI), whatever the app language is.
    var isolatedByContent: String { "\u{2068}\(self)\u{2069}" }

    /// The direction of the first letter that has one: right to left for Arabic (and Hebrew, Syriac,
    /// Thaana…) script, left to right for the others; nil without any letter (digits, emoji).
    var naturalLayoutDirection: LayoutDirection? {
        for scalar in unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return .rightToLeft
            default: return .leftToRight
            }
        }
        return nil
    }
}

extension View {
    /// Lays out text written by members in its own direction (api-guide.md: "text written by members in
    /// French still needs natural alignment"): a French bio starts at the left in the Arabic app.
    func naturalDirection(of text: String) -> some View {
        modifier(NaturalDirection(direction: text.naturalLayoutDirection))
    }
}

private struct NaturalDirection: ViewModifier {
    let direction: LayoutDirection?
    @Environment(\.layoutDirection) private var current

    func body(content: Content) -> some View {
        content.environment(\.layoutDirection, direction ?? current)
    }
}
