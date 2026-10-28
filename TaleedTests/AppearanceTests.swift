import SwiftUI
@testable import Taleed
import Testing
import UIKit

/// The Appearance setting (design/dark-mode.md): Light by default, kept on the device, applied at once.
@MainActor
struct AppearanceTests {
    private func freshDefaults() -> UserDefaults {
        let name = "AppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func lightIsTheDefault() {
        let manager = AppearanceManager(defaults: freshDefaults())
        #expect(manager.appearance == .light)
        #expect(manager.colorScheme == .light)
        #expect(AppearanceManager.resolve(stored: nil) == .light)
        #expect(AppearanceManager.resolve(stored: "sepia") == .light)
    }

    @Test func theChoiceIsStoredAndReadBack() {
        let defaults = freshDefaults()
        let manager = AppearanceManager(defaults: defaults)
        manager.applyToWindows = { _ in }
        manager.select(.dark)
        #expect(defaults.string(forKey: AppearanceManager.storageKey) == "dark")
        // A new launch reads it back.
        #expect(AppearanceManager(defaults: defaults).appearance == .dark)
        manager.select(.light)
        #expect(AppearanceManager(defaults: defaults).appearance == .light)
    }

    @Test func aChangeAppliesAtOnce() {
        let manager = AppearanceManager(defaults: freshDefaults())
        var applied: [UIUserInterfaceStyle] = []
        manager.applyToWindows = { applied.append($0) }
        manager.select(.dark)
        #expect(manager.colorScheme == .dark)
        #expect(applied == [.dark])
        // The same choice again changes nothing.
        manager.select(.dark)
        #expect(applied == [.dark])
        manager.select(.light)
        #expect(manager.colorScheme == .light)
        #expect(applied == [.dark, .light])
    }

    @Test func eachChoiceHasItsLabelInEveryLanguage() {
        #expect(AppAppearance.allCases == [.light, .dark])
        let expected: [AppLanguage: [String]] = [.en: ["Light", "Dark"], .fr: ["Clair", "Sombre"], .ar: ["فاتح", "داكن"]]
        for (language, labels) in expected {
            #expect(AppAppearance.allCases.map { LanguageManager.localizedString($0.titleKey, language: language) } == labels)
        }
        #expect(LanguageManager.localizedString(.appSettingsAppearance, language: .en) == "Appearance")
        #expect(LanguageManager.localizedString(.appSettingsAppearance, language: .fr) == "Apparence")
        #expect(LanguageManager.localizedString(.appSettingsAppearance, language: .ar) == "المظهر")
    }

    /// The tokens resolve to their light value in light and their dark value in dark.
    @Test func tokensFollowTheColourScheme() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        for token in TaleedColor.catalog + TaleedColor.appCatalog {
            let color = UIColor(token.color)
            #expect(Self.hex(color.resolvedColor(with: light)) == token.hex, "\(token.name) light")
            #expect(Self.hex(color.resolvedColor(with: dark)) == token.darkHex, "\(token.name) dark")
        }
    }

    /// dark-mode.md's values, and the measured text pairs pass WCAG AA in dark.
    @Test func darkPaletteMatchesTheSpec() throws {
        let dark = { (name: String) in (TaleedColor.catalog + TaleedColor.appCatalog).first { $0.name == name }?.darkHex }
        #expect(dark("brandPrimary") == 0x7C9BFF)
        #expect(dark("onBrandPrimary") == 0x0B1120)
        #expect(dark("surfacePrimary") == 0x121A2E)
        #expect(dark("surfaceGrouped") == 0x0B1120)
        #expect(dark("surfaceElevated") == 0x1A2338)
        #expect(dark("borderField") == 0x4A5675)
        #expect(dark("textPrimary") == 0xEEF1F8)
        #expect(dark("feedbackError") == 0xFF7A8C)
        #expect(dark("onFeedbackError") == 0x0B1120)
        #expect(dark("onBrandAccent") == 0x0B1120)
        #expect(dark("brandAccentPressed") == 0x4CD39F)
        #expect(dark("linkDisabled") == 0x8A94AC)
        #expect(dark("imageRemoveScrim") == 0x000000)
        let light = { (name: String) in (TaleedColor.catalog + TaleedColor.appCatalog).first { $0.name == name }?.hex }
        #expect(light("onBrandAccent") == 0x032117)
        #expect(light("brandAccentPressed") == 0x4AB08B)
        #expect(light("linkDisabled") == 0xACC8FF)
        let pairs: [(String, String)] = [
            ("textPrimary", "surfacePrimary"), ("textBody", "surfacePrimary"), ("textSecondary", "surfacePrimary"),
            ("textSecondary", "surfaceElevated"), ("brandPrimary", "surfacePrimary"), ("feedbackError", "surfacePrimary"),
            ("onBrandPrimary", "brandPrimary"), ("brandDark", "brandSoft"), ("warningText", "warningSoft"),
            ("feedbackSuccess", "successSoft"), ("feedbackError", "errorSoft"), ("textSecondarySmall", "brandSoft"),
            ("onFeedbackError", "feedbackError"), ("brandEmphasis", "brandTint"), ("navInactive", "surfaceElevated"),
            ("mintOnTint", "mintTint"), ("infoText", "brandTintStrong"), ("onInverseFill", "inverseFill"),
            ("onBrandAccent", "brandAccent"), ("onBrandAccent", "brandAccentPressed"), ("linkDisabled", "brandTint"),
        ]
        for (text, surface) in pairs {
            let ratio = try Self.contrast(#require(dark(text)), #require(dark(surface)))
            #expect(ratio >= 4.5, "\(text) on \(surface): \(ratio)")
        }
    }

    private static func hex(_ color: UIColor) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
    }

    private static func luminance(_ hex: UInt32) -> Double {
        let channels = [hex >> 16, hex >> 8, hex].map { Double($0 & 0xFF) / 255 }
        let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    private static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (lighter + 0.05) / (darker + 0.05)
    }
}
