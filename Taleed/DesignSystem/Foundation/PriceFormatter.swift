import Foundation

/// Formats prices in Algerian dinars with the "DA" suffix (decision D-5), as the website does:
///
/// - French and English: digits grouped by a narrow no-break space, then a no-break space and "DA":
///   `12 500 DA` (the website's `fr-DZ` output).
/// - Arabic: the website's `ar-DZ` output: Latin digits grouped by ".", then "د.ج.", wrapped in
///   right-to-left marks: `‏12.500 د.ج.‏`.
///
/// Amounts are whole dinars (the API's integer amounts).
enum PriceFormatter {
    private static let narrowNoBreakSpace = "\u{202F}"
    private static let noBreakSpace = "\u{00A0}"
    private static let rightToLeftMark = "\u{200F}"
    private static let leftToRightMark = "\u{200E}"

    static func format(_ amount: Int, language: AppLanguage) -> String {
        switch language {
        case .fr, .en:
            let sign = amount < 0 ? "-" : ""
            return sign + grouped(abs(amount), separator: narrowNoBreakSpace) + noBreakSpace + "DA"
        case .ar:
            let sign = amount < 0 ? leftToRightMark + "-" : ""
            return rightToLeftMark + sign + grouped(abs(amount), separator: ".") + noBreakSpace + "د.ج." + rightToLeftMark
        }
    }

    static func format(_ amount: Int, locale: Locale) -> String {
        format(amount, language: AppLanguage(locale: locale))
    }

    /// A whole number grouped as prices are, without the currency: `2 000` (narrow no-break space) in
    /// French and English, `2.000` in Arabic (the website's `ar-DZ`). For counts and limits in messages.
    static func number(_ value: Int, language: AppLanguage) -> String {
        let sign = value < 0 ? "-" : ""
        return sign + grouped(abs(value), separator: language == .ar ? "." : narrowNoBreakSpace)
    }

    /// Groups the digits by three from the right: `1234567` → `1 234 567`.
    private static func grouped(_ value: Int, separator: String) -> String {
        let digits = Array(String(value))
        var groups: [String] = []
        var end = digits.count
        while end > 0 {
            let start = max(0, end - 3)
            groups.insert(String(digits[start..<end]), at: 0)
            end = start
        }
        return groups.joined(separator: separator)
    }
}
