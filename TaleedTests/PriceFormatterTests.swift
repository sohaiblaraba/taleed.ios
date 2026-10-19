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
}
