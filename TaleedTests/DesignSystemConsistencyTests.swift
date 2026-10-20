import Foundation
import SwiftUI
@testable import Taleed
import Testing

/// The design system matches the Android app: string keys and values, plurals, token names,
/// button types, and the rules that keep prices and labels whole.
struct DesignSystemConsistencyTests {
    private let english = Locale(identifier: "en")
    private let french = Locale(identifier: "fr")
    private let arabic = Locale(identifier: "ar")

    @Test func pluralsResolveInEveryLanguage() {
        #expect(DesignSystemStrings.format(.favoriteCount, locale: english, 1) == "1 favorite")
        #expect(DesignSystemStrings.format(.favoriteCount, locale: english, 7) == "7 favorites")
        #expect(DesignSystemStrings.format(.favoriteCount, locale: french, 7) == "7 favoris")
        #expect(DesignSystemStrings.format(.favoriteCount, locale: arabic, 2) == "مفضلتان")
        #expect(DesignSystemStrings.format(.photoUploaderZoneTitle, locale: english, 5) == "Upload up to 5 images")
        #expect(DesignSystemStrings.format(.photoUploaderHelperFull, locale: english, 1) == "Photo added. Remove it to add another.")
    }

    @Test func numberedAndObjectArgumentsFormat() {
        #expect(DesignSystemStrings.format(.photoUploaderRemove, locale: english, 2) == "Remove photo 2")
        #expect(DesignSystemStrings.format(.photoUploaderMakeCover, locale: english, 3) == "Make photo 3 the cover")
        #expect(DesignSystemStrings.format(.commonRemoveFilter, locale: english, "Oran") == "Remove filter Oran")
        #expect(DesignSystemStrings.format(.photoUploaderCount, locale: english, 3, 5) == "3 / 5")
    }

    /// Values that used to differ from Android's strings.xml.
    @Test func valuesMatchAndroid() {
        #expect(DesignSystemStrings.string(.authSignIn, locale: english) == "Sign in")
        #expect(DesignSystemStrings.string(.authSignOut, locale: english) == "Sign out")
        #expect(DesignSystemStrings.string(.authSignInRequired, locale: english) == "Sign in to continue.")
        #expect(DesignSystemStrings.string(.trustTrustedSellers, locale: french) == "Vendeurs fiables")
        #expect(DesignSystemStrings.string(.commonErrorGeneric, locale: french) == "Une erreur est survenue. Réessayez.")
        #expect(DesignSystemStrings.string(.commonErrorGeneric, locale: arabic) == "حدث خطأ. أعد المحاولة.")
        #expect(DesignSystemStrings.string(.appErrorInvalidState, locale: french)
            == "Cette action n’est plus possible. La page a été mise à jour.")
        #expect(DesignSystemStrings.string(.homeHeroTitle, locale: french) == "Donnez une seconde vie à vos affaires.")
        #expect(DesignSystemStrings.format(.checkoutSuccessBody, locale: english, 1)
            == "Your money is safe. The seller now has 1 day to ship your order.")
        #expect(DesignSystemStrings.format(.checkoutSuccessBody, locale: french, 3)
            == "Votre argent est en sécurité. Le vendeur a maintenant 3 jours pour expédier votre commande.")
    }

    @Test func sizeAndLayoutTokensAreFlattened() {
        #expect(TaleedSize.buttonSmallHeight == 32)
        #expect(TaleedSize.buttonHyperlinkHeightMediumLarge == 36)
        #expect(TaleedSize.bottomSheetHandleWidth == 40)
        #expect(TaleedLayout.pageHeadingPaddingTop == 24)
        #expect(TaleedLayout.productGridColumns == 2)
        // size.heroBanner.padding "24/20".
        #expect(TaleedSize.heroBannerPaddingY == 24 && TaleedSize.heroBannerPaddingX == 20)
    }

    /// tokens.json keeps `phosphorDefault` as a Figma leftover, not a token.
    @Test func figmaLeftoversAreNotTokens() {
        #expect(!TaleedColor.catalog.contains { $0.name == "phosphorDefault" })
    }

    @Test func outlineAndUnderlinedLinkFollowAndroid() {
        #expect(TaleedButtonColors.of(.outline, .pressed).fill == TaleedColor.surfaceGrouped)
        #expect(TaleedButtonColors.of(.outline, .disabled).content == TaleedColor.navy300)
        #expect(TaleedButtonColors.of(.hyperlinkUnderlined, .normal).content == TaleedColor.blue900)
        #expect(TaleedButtonMetrics.of(.outline, .medium).paddingX == 16)
        #expect(TaleedButtonMetrics.of(.outline, .large).paddingX == 24)
        #expect(TaleedButtonMetrics.of(.outline, .large).radius == TaleedRadius.m)
        #expect(TaleedButtonMetrics.of(.secondary, .large).radius == TaleedRadius.s)
    }

    /// A price may break only before the currency: digit groups and "DA" / "د.ج." stay whole.
    @Test func pricesBreakOnlyBeforeTheCurrency() {
        let french = PriceText.breakableBeforeCurrency(PriceFormatter.format(1_234_567, language: .fr))
        #expect(french == "1\u{202F}234\u{202F}567 DA")
        #expect(french.split(separator: " ").count == 2)
        let arabic = PriceText.breakableBeforeCurrency(PriceFormatter.format(12500, language: .ar))
        #expect(arabic == "\u{200F}12.500 د.ج.\u{200F}")
    }

    @Test @MainActor func widestWordGrowsWithTheTextSize() {
        let small = WordFittingText.widestWord(in: "Neuf, étiqueté", style: TaleedFont.tagLabel, sizeCategory: .large)
        let large = WordFittingText.widestWord(in: "Neuf, étiqueté", style: TaleedFont.tagLabel,
                                               sizeCategory: .accessibilityExtraExtraExtraLarge)
        let whole = TaleedFont.tagLabel.width(of: "Neuf, étiqueté", sizeCategory: .large)
        #expect(small > 0 && small < whole)
        #expect(large > small * 1.5)
    }

    @Test @MainActor func toastsStackUpToThree() {
        let state = TaleedToastState()
        for index in 0..<4 {
            state.show(ToastItem(kind: .success, message: "\(index)"))
        }
        #expect(state.toasts.map(\.message) == ["1", "2", "3"])
        state.dismiss(state.toasts[0].id)
        #expect(state.toasts.map(\.message) == ["2", "3"])
    }
}
