import Foundation
@testable import Taleed
import Testing

/// Prices use the "DA" suffix (decision D-5) and match the website's `formatDZD` output.
struct PriceFormatterTests {
    private let narrowSpace = "\u{202F}"
    private let noBreakSpace = "\u{00A0}"
    private let rightToLeftMark = "\u{200F}"

    @Test func frenchGroupsWithNarrowSpaceAndSuffixesDA() {
        #expect(PriceFormatter.format(1500, language: .fr) == "1\(narrowSpace)500\(noBreakSpace)DA")
        #expect(PriceFormatter.format(12500, language: .fr) == "12\(narrowSpace)500\(noBreakSpace)DA")
        #expect(PriceFormatter.format(1_234_567, language: .fr) == "1\(narrowSpace)234\(narrowSpace)567\(noBreakSpace)DA")
    }

    @Test func smallAmountsHaveNoGroupSeparator() {
        #expect(PriceFormatter.format(800, language: .fr) == "800\(noBreakSpace)DA")
        #expect(PriceFormatter.format(0, language: .fr) == "0\(noBreakSpace)DA")
    }

    @Test func englishUsesTheSameDASuffix() {
        #expect(PriceFormatter.format(12500, language: .en) == PriceFormatter.format(12500, language: .fr))
    }

    @Test func arabicMatchesTheWebsitesArDZOutput() {
        // Intl.NumberFormat("ar-DZ", { style: "currency", currency: "DZD", maximumFractionDigits: 0 }).format(12500)
        #expect(PriceFormatter.format(12500, language: .ar) == "\(rightToLeftMark)12.500\(noBreakSpace)د.ج.\(rightToLeftMark)")
        #expect(PriceFormatter.format(800, language: .ar) == "\(rightToLeftMark)800\(noBreakSpace)د.ج.\(rightToLeftMark)")
    }

    @Test func negativeAmountsKeepTheSign() {
        #expect(PriceFormatter.format(-1500, language: .fr) == "-1\(narrowSpace)500\(noBreakSpace)DA")
        #expect(PriceFormatter.format(-1500, language: .ar).contains("-1.500"))
    }

    @Test func localeSelectsTheLanguage() {
        #expect(PriceFormatter.format(4800, locale: Locale(identifier: "ar-DZ")) == PriceFormatter.format(4800, language: .ar))
        #expect(PriceFormatter.format(4800, locale: Locale(identifier: "de")) == PriceFormatter.format(4800, language: .fr))
    }

    @Test func anArabicSentenceDoesNotRepeatTheCurrencysPeriod() {
        let low = PriceFormatter.format(750, language: .ar)
        let high = PriceFormatter.format(2500, language: .ar)
        let range = withoutMarks(DesignSystemStrings.format(.offersErrorRange, locale: AppLanguage.ar.locale, low, high))
        #expect(!range.contains(".."))
        #expect(range.hasSuffix("2.500\u{00A0}د.ج."))
        let hint = withoutMarks(DesignSystemStrings.format(.offersOfferHint, locale: AppLanguage.ar.locale, high))
        #expect(hint.contains("د.ج. "))
        #expect(!hint.contains(".."))
        // French keeps its period after "DA".
        let french = DesignSystemStrings.format(.offersOfferHint, locale: AppLanguage.fr.locale,
                                                PriceFormatter.format(2500, language: .fr))
        #expect(withoutMarks(french).contains("DA."))
    }

    private func withoutMarks(_ text: String) -> String {
        var result = ""
        result.unicodeScalars.append(contentsOf: text.unicodeScalars.filter {
            !(0x200E...0x200F).contains($0.value) && !(0x2066...0x2069).contains($0.value)
        })
        return result
    }
}
