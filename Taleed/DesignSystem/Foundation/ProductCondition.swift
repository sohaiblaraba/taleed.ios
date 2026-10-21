import Foundation

/// The five item conditions, by API code (decision D-8). Each has a short label (22 pt tag on cards
/// and photos), a full label (30 pt tag in list rows, search results and detail) and tag colours.
enum ProductCondition: String, CaseIterable, Sendable {
    case newWithTags = "NEW_WITH_TAGS"
    case newWithoutTags = "NEW_WITHOUT_TAGS"
    case veryGood = "VERY_GOOD"
    case good = "GOOD"
    case satisfactory = "SATISFACTORY"

    /// Which of the two labels a tag shows.
    enum LabelLength: Sendable {
        /// "New, tagged", "New", "Very good", "Good", "Fair": the catalog's `shortLabel` (the website's
        /// `short…` labels).
        case short
        /// "New with tags", "New without tags", "Very good condition", "Good condition", "Fair condition"
        /// (fr/ar: the website's full labels, the same as the catalog's `label`; the sell picker too).
        case full
    }

    /// The condition of an API code, nil for a code the app does not know yet.
    init?(code: String) {
        self.init(rawValue: code)
    }

    func labelKey(_ length: LabelLength) -> L10nKey {
        switch (self, length) {
        case (.newWithTags, .short): .conditionShortNewWithTags
        case (.newWithoutTags, .short): .conditionShortNewWithoutTags
        case (.veryGood, .short): .conditionShortVeryGood
        case (.good, .short): .conditionShortGood
        case (.satisfactory, .short): .conditionShortSatisfactory
        case (.newWithTags, .full): .conditionNewWithTags
        case (.newWithoutTags, .full): .conditionNewWithoutTags
        case (.veryGood, .full): .conditionVeryGood
        case (.good, .full): .conditionGood
        case (.satisfactory, .full): .conditionSatisfactory
        }
    }

    func label(_ length: LabelLength = .short, in language: AppLanguage) -> String {
        DesignSystemStrings.string(labelKey(length), language: language)
    }

    /// The label of an API code. Known codes use the app strings: in fr and ar they are the catalog's
    /// `shortLabel` / `label`; in en the full labels name the condition ("Very good condition", where
    /// the catalog says "Very good"), so that all five read alike.
    /// An unknown code shows the catalog's `shortLabel` (short tags, decision 6), then its `label`.
    static func label(code: String, catalogLabel: String, catalogShortLabel: String? = nil,
                      length: LabelLength = .short, language: AppLanguage) -> String {
        if let condition = ProductCondition(code: code) { return condition.label(length, in: language) }
        if length == .short, let catalogShortLabel, !catalogShortLabel.isEmpty { return catalogShortLabel }
        return catalogLabel
    }
}
