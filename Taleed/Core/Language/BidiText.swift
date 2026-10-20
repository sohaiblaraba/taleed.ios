import SwiftUI

extension String {
    /// Keeps a left-to-right run, such as `@amina` or an email address, in order inside
    /// right-to-left text (Unicode LRI ... PDI). Without it, Arabic shows `amina@`.
    var isolatedLeftToRight: String { "\u{2066}\(self)\u{2069}" }

    /// Gives text written by members the direction of its own first strong letter
    /// (Unicode FSI ... PDI), whatever the app language is.
    var isolatedByContent: String { "\u{2068}\(self)\u{2069}" }

    /// Text built from a format, laid out in the app language's direction. `String(format:locale:)` wraps
    /// each `%@` argument in an isolate (FSI ... PDI), so an Arabic format that starts with one ("%1$@ (%2$d)")
    /// has no strong letter left outside it and would run left to right ("(5) معروض للبيع"). Arabic text
    /// whose first letter outside the isolates is left to right, or that has letters only inside
    /// isolates, gets a leading right-to-left mark (RLM). Digits alone ("3 / 5") stay as they are.
    func inParagraphDirection(of language: AppLanguage) -> String {
        guard language.layoutDirection == .rightToLeft else { return self }
        switch paragraphStart {
        case .letter(.leftToRight), .isolatesOnly: return "\u{200F}" + self
        case .letter, .none: return self
        }
    }

    private enum ParagraphStart {
        /// The first letter (or mark) outside isolates, and its direction (Unicode rule P2).
        case letter(LayoutDirection)
        /// No letter outside isolates, but an isolate: nothing gives the paragraph a direction.
        case isolatesOnly
        case none
    }

    private var paragraphStart: ParagraphStart {
        var depth = 0
        var hasIsolate = false
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x2066...0x2068:
                depth += 1
                hasIsolate = true
            case 0x2069: depth = max(0, depth - 1)
            case 0x200F where depth == 0: return .letter(.rightToLeft)
            case 0x200E where depth == 0: return .letter(.leftToRight)
            default:
                guard depth == 0, scalar.properties.isAlphabetic,
                      let direction = String(scalar).naturalLayoutDirection else { continue }
                return .letter(direction)
            }
        }
        return hasIsolate ? .isolatesOnly : .none
    }

    /// An Arabic price ends with the currency's own period ("2.500 د.ج."), so a sentence that puts its
    /// period right after one would read "د.ج..": the sentence's period is dropped (direction marks and
    /// the end of an isolate in between are kept).
    var droppingPeriodAfterArabicCurrency: String {
        let currency = Array("د.ج.".unicodeScalars)
        let transparent: Set<UInt32> = [0x200E, 0x200F, 0x2069]
        var scalars = Array(unicodeScalars)
        guard scalars.count > currency.count else { return self }
        var index = 0
        while index + currency.count <= scalars.count {
            guard scalars[index..<index + currency.count].elementsEqual(currency) else {
                index += 1
                continue
            }
            var next = index + currency.count
            while next < scalars.count, transparent.contains(scalars[next].value) { next += 1 }
            if next < scalars.count, scalars[next] == "." { scalars.remove(at: next) }
            index += currency.count
        }
        var result = ""
        result.unicodeScalars.append(contentsOf: scalars)
        return result
    }

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
