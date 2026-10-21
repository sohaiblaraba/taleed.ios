import Foundation
@testable import Taleed
import Testing

/// Condition codes map to the short and full labels in order (decision D-8).
struct ProductConditionTests {
    @Test func codesMapToConditions() {
        #expect(ProductCondition(code: "NEW_WITH_TAGS") == .newWithTags)
        #expect(ProductCondition(code: "NEW_WITHOUT_TAGS") == .newWithoutTags)
        #expect(ProductCondition(code: "VERY_GOOD") == .veryGood)
        #expect(ProductCondition(code: "GOOD") == .good)
        #expect(ProductCondition(code: "SATISFACTORY") == .satisfactory)
        #expect(ProductCondition(code: "LIKE_NEW") == nil)
    }

    @Test func englishLabelsReadAlike() {
        #expect(ProductCondition.allCases.map { $0.label(.short, in: .en) } ==
            ["New, tagged", "New", "Very good", "Good", "Fair"])
        #expect(ProductCondition.allCases.map { $0.label(.full, in: .en) } ==
            ["New with tags", "New without tags", "Very good condition", "Good condition", "Fair condition"])
    }

    @Test func frenchAndArabicShortLabelsAreTheWebsiteShortLabels() {
        #expect(ProductCondition.allCases.map { $0.label(.short, in: .fr) } ==
            ["Neuf, étiqueté", "Neuf", "Très bon", "Bon", "Correct"])
        #expect(ProductCondition.allCases.map { $0.label(.short, in: .ar) } ==
            ["جديد بعلامة", "جديد", "ممتاز", "جيد", "مقبول"])
    }

    @Test func frenchAndArabicFullLabelsAreTheWebsiteLabels() {
        #expect(ProductCondition.allCases.map { $0.label(.full, in: .fr) } ==
            ["Neuf avec étiquette", "Neuf sans étiquette", "Très bon état", "Bon état", "État satisfaisant"])
        #expect(ProductCondition.allCases.map { $0.label(.full, in: .ar) } ==
            ["جديد مع البطاقة", "جديد بدون بطاقة", "حالة ممتازة", "حالة جيدة", "حالة مقبولة"])
    }

    @Test func unknownCodeUsesTheCatalogLabels() {
        #expect(ProductCondition.label(code: "REFURBISHED", catalogLabel: "Reconditionné", catalogShortLabel: "Reconditionné court",
                                       language: .fr) == "Reconditionné court")
        #expect(ProductCondition.label(code: "REFURBISHED", catalogLabel: "Reconditionné", language: .fr) == "Reconditionné")
        #expect(ProductCondition.label(code: "REFURBISHED", catalogLabel: "Reconditionné", catalogShortLabel: "court",
                                       length: .full, language: .fr) == "Reconditionné")
        #expect(ProductCondition.label(code: "GOOD", catalogLabel: "ignored", catalogShortLabel: "ignored", language: .en) == "Good")
    }

    @Test func tagTonesFollowTheSpec() {
        #expect(ProductCondition.newWithTags.tone == .brand)
        #expect(ProductCondition.newWithoutTags.tone == .success)
        #expect(ProductCondition.veryGood.tone == .success)
        #expect(ProductCondition.good.tone == .warning)
        #expect(ProductCondition.satisfactory.tone == .neutral)
    }

    /// The same rule as Android's `avatarInitials`, so a member gets the same initials on both apps.
    @Test func avatarInitials() {
        #expect(TaleedAvatar.initials(from: "Lina N.") == "LN")
        #expect(TaleedAvatar.initials(from: "saf") == "S")
        #expect(TaleedAvatar.initials(from: "Nabia Tariq Benali") == "NT")
        #expect(TaleedAvatar.initials(from: "amina_b") == "AB")
        #expect(TaleedAvatar.initials(from: "@lina.n") == "LN")
        #expect(TaleedAvatar.initials(from: "@") == "?")
        #expect(TaleedAvatar.initials(from: "") == "?")
    }
}
