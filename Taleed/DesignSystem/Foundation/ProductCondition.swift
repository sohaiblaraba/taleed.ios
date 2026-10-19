import Foundation

/// The five item conditions, by API code (decision D-8). Each has a short label in the app strings
/// and the colours of its tag.
enum ProductCondition: String, CaseIterable, Sendable {
    case newWithTags = "NEW_WITH_TAGS"
    case newWithoutTags = "NEW_WITHOUT_TAGS"
    case veryGood = "VERY_GOOD"
    case good = "GOOD"
    case satisfactory = "SATISFACTORY"

    /// The condition of an API code, nil for a code the app does not know yet.
    init?(code: String) {
        self.init(rawValue: code)
    }

    /// The string key of the short label: "New, tagged", "Like new", "Very good", "Good", "Fair" in English.
    var labelKey: L10nKey {
        switch self {
        case .newWithTags: .conditionNewWithTags
        case .newWithoutTags: .conditionNewWithoutTags
        case .veryGood: .conditionVeryGood
        case .good: .conditionGood
        case .satisfactory: .conditionSatisfactory
        }
    }

    func label(in language: AppLanguage) -> String {
        DesignSystemStrings.string(labelKey, language: language)
    }

    /// The short label of an API code, or `fallback` (the catalog's full label) for an unknown code.
    static func label(code: String, fallback: String, language: AppLanguage) -> String {
        ProductCondition(code: code)?.label(in: language) ?? fallback
    }
}
