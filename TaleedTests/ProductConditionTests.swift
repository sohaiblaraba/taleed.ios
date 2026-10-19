import Foundation
@testable import Taleed
import Testing

/// Condition codes map to the Figma short labels in order (decision D-8).
struct ProductConditionTests {
    @Test func codesMapToConditions() {
        #expect(ProductCondition(code: "NEW_WITH_TAGS") == .newWithTags)
        #expect(ProductCondition(code: "NEW_WITHOUT_TAGS") == .newWithoutTags)
        #expect(ProductCondition(code: "VERY_GOOD") == .veryGood)
        #expect(ProductCondition(code: "GOOD") == .good)
        #expect(ProductCondition(code: "SATISFACTORY") == .satisfactory)
        #expect(ProductCondition(code: "LIKE_NEW") == nil)
    }

    @Test func englishLabelsAreTheFigmaShortLabels() {
        let labels = ProductCondition.allCases.map { $0.label(in: .en) }
        #expect(labels == ["New, tagged", "Like new", "Very good", "Good", "Fair"])
    }

    @Test func frenchAndArabicLabelsComeFromTheWebsite() {
        #expect(ProductCondition.allCases.map { $0.label(in: .fr) } ==
            ["Neuf avec étiquette", "Neuf sans étiquette", "Très bon état", "Bon état", "État satisfaisant"])
        #expect(ProductCondition.veryGood.label(in: .ar) == "حالة ممتازة")
    }

    @Test func unknownCodeFallsBackToTheCatalogLabel() {
        #expect(ProductCondition.label(code: "REFURBISHED", fallback: "Reconditionné", language: .fr) == "Reconditionné")
        #expect(ProductCondition.label(code: "GOOD", fallback: "ignored", language: .en) == "Good")
    }

    @Test func tagTonesFollowTheSpec() {
        #expect(ProductCondition.newWithTags.tone == .brand)
        #expect(ProductCondition.newWithoutTags.tone == .success)
        #expect(ProductCondition.veryGood.tone == .success)
        #expect(ProductCondition.good.tone == .warning)
        #expect(ProductCondition.satisfactory.tone == .neutral)
    }

    @Test func avatarInitials() {
        #expect(TaleedAvatar.initials(from: "Lina N.") == "LN")
        #expect(TaleedAvatar.initials(from: "saf") == "S")
        #expect(TaleedAvatar.initials(from: "Nabia Tariq Benali") == "NT")
        #expect(TaleedAvatar.initials(from: "") == "")
    }
}
