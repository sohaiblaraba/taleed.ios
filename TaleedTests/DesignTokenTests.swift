import CoreText
import SwiftUI
@testable import Taleed
import Testing
import UIKit

/// Sanity checks of the generated tokens against design/tokens.json and of the bundled resources.
struct DesignTokenTests {
    private func hex(_ name: String) -> UInt32? {
        TaleedColor.catalog.first { $0.name == name }?.hex
    }

    @Test func semanticColoursHaveTheirFigmaValues() {
        #expect(hex("brandPrimary") == 0x2455F5)
        #expect(hex("brandPrimary") == hex("blue500"))
        #expect(hex("brandAccent") == hex("mint400"))
        #expect(hex("textPrimary") == hex("navy900"))
        #expect(hex("textSecondary") == 0x778198)
        #expect(hex("borderSubtle") == 0xDDE2EC)
        #expect(hex("feedbackSuccess") == 0x139A6C)
        #expect(hex("feedbackWarning") == 0xF6B73C)
        #expect(hex("feedbackError") == 0xDC3C52)
        #expect(hex("textBody") == hex("neutral700"))
        #expect(hex("surfaceGrouped") == hex("neutral50"))
    }

    @Test func everyScaleHasElevenSteps() {
        for scale in ["blue", "mint", "navy", "neutral"] {
            #expect(TaleedColor.catalog.filter { $0.group == scale }.count == 11)
        }
    }

    @Test func colourNamesAreUnique() {
        let names = TaleedColor.catalog.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func textStylesMatchTheFigmaStyles() {
        #expect(TaleedFont.display.size == 36 && TaleedFont.display.weight == .semibold && TaleedFont.display.lineHeight == 43.2)
        #expect(TaleedFont.title1.size == 28 && TaleedFont.title1.lineHeight == nil)
        #expect(TaleedFont.bodyRegular.size == 14 && TaleedFont.bodyRegular.weight == .regular)
        #expect(TaleedFont.caption.size == 12 && TaleedFont.caption.weight == .semibold)
        #expect(TaleedFont.buttonLarge.size == 16 && TaleedFont.buttonLarge.weight == .semibold)
        #expect(TaleedFont.priceCard.weight == .extrabold)
        #expect(TaleedFont.eyebrow.letterSpacing == 0.55)
        #expect(TaleedFont.catalog.count == 29)
    }

    @Test func spacingRadiusAndSizes() {
        #expect(TaleedSpacing.catalog.map(\.value) == [4, 8, 12, 16, 24, 32, 48])
        #expect(TaleedRadius.catalog.map(\.value) == [6, 10, 14, 20, 28, 999])
        #expect(TaleedSize.touchTargetMin == 44)
        #expect(TaleedSize.appBarHeight == 56)
        #expect(TaleedSize.bottomNavHeight == 77)
        #expect([TaleedButtonSize.small, .medium, .large].map(\.height) == [32, 40, 48])
        #expect(TaleedSize.inputHeight == 44)
        #expect(TaleedSize.photoUploaderMaxPhotos == 5)
        #expect(TaleedOpacity.disabledField == 0.55)
    }

    @Test func motion() {
        #expect(TaleedMotion.transitionMin == 0.18)
        #expect(TaleedMotion.transitionMax == 0.24)
        #expect(TaleedMotion.toastAutoDismiss == 4)
        #expect(TaleedMotion.skeletonPulse == 1.2)
        #expect(TaleedMotion.skeletonMaxPlaceholders == 6)
    }

    @Test func shadowsUseHalfTheFigmaBlur() {
        #expect(TaleedElevation.level1.blur == 8 && TaleedElevation.level1.y == 2 && TaleedElevation.level1.opacity == 0.07)
        #expect(TaleedElevation.level2.blur == 28 && TaleedElevation.level2.opacity == 0.09)
        #expect(TaleedElevation.navTop.y == -4)
    }

    @Test @MainActor func allBrandFacesAreRegistered() {
        for typeface in TaleedTypeface.allCases {
            for weight in TaleedFontWeight.allCases {
                #expect(UIFont(name: typeface.postScriptName(weight), size: 12) != nil, "\(typeface.postScriptName(weight))")
            }
        }
    }

    /// Plus Jakarta Sans is the primary face in every language; Arabic script cascades to Alexandria.
    @Test @MainActor func arabicScriptCascadesToAlexandria() {
        let font = TaleedFont.title1.uiFont()
        #expect(font.fontName == "PlusJakartaSans-SemiBold")
        let arabic = "تليد" as NSString
        let arabicFace = CTFontCreateForString(font as CTFont, arabic, CFRange(location: 0, length: arabic.length))
        #expect(CTFontCopyPostScriptName(arabicFace) as String == "Alexandria-SemiBold")
        let latin = "2 500 DA" as NSString
        let latinFace = CTFontCreateForString(font as CTFont, latin, CFRange(location: 0, length: latin.length))
        #expect(CTFontCopyPostScriptName(latinFace) as String == "PlusJakartaSans-SemiBold")
        #expect(Locale(identifier: "ar").isArabic && !Locale(identifier: "fr").isArabic)
    }

    @Test func allIconsAndImagesAreInTheCatalog() {
        #expect(TaleedIcon.allCases.count == 60)
        for icon in TaleedIcon.allCases {
            #expect(UIImage(named: icon.assetName) != nil, "\(icon.assetName)")
        }
        for image in TaleedImage.allCases {
            #expect(UIImage(named: image.assetName) != nil, "\(image.assetName)")
        }
    }

    @Test func onlyDirectionalIconsMirror() {
        #expect(TaleedIcon.allCases.filter(\.isDirectional) ==
            [.arrowLeft, .arrowLeftLight, .arrowRight, .caretLeft, .caretLeftLight, .caretRight])
    }

    @Test func everyStringKeyIsTranslated() {
        for language in AppLanguage.allCases {
            for key in L10nKey.allCases {
                #expect(LanguageManager.localizedString(key, language: language) != key.rawValue, "\(key.rawValue) \(language)")
            }
        }
    }

    @Test func buttonColoursFollowTheSpecTable() {
        #expect(TaleedButtonColors.of(.secondary, .normal) ==
            TaleedButtonColors(fill: TaleedColor.mint400, border: TaleedColor.mint500, content: TaleedColor.mint900))
        #expect(TaleedButtonColors.of(.danger, .pressed).fill == TaleedColor.dangerPressed)
        #expect(TaleedButtonColors.of(.hyperlink, .normal).fill == nil)
    }
}
