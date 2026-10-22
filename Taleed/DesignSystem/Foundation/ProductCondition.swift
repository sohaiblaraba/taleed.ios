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
        /// "New, tagged", "Like new", "Very good", "Good", "Fair": the catalog's `shortLabel` (the website's
        /// `short…` labels; English "Like new" from the server, E-6).
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

    /// The label of an API code. Short tags show the catalog's `shortLabel` whenever it is known
    /// (decision 6, E-6: English "Like new" comes from the server), else the app's short string for a
    /// known code (the same words, for before the catalog loads). Full labels use the app strings for
    /// known codes: in fr and ar the catalog's `label`; in en they name the condition ("Very good
    /// condition"), so that all five read alike. An unknown code shows the catalog's `label`.
    /// Android's `ItemCondition.label` follows the same rule.
    static func label(code: String, catalogLabel: String, catalogShortLabel: String? = nil,
                      length: LabelLength = .short, language: AppLanguage) -> String {
        if length == .short, let catalogShortLabel, !catalogShortLabel.isEmpty { return catalogShortLabel }
        if let condition = ProductCondition(code: code) { return condition.label(length, in: language) }
        return catalogLabel
    }
}
