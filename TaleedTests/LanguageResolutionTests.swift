import Foundation
@testable import Taleed
import Testing

struct LanguageResolutionTests {
    @Test func arabicRegionResolvesToArabic() {
        #expect(LanguageManager.resolve(stored: nil, preferredLanguages: ["ar-DZ"]) == .ar)
    }

    @Test func englishRegionResolvesToEnglish() {
        #expect(LanguageManager.resolve(stored: nil, preferredLanguages: ["en-GB"]) == .en)
    }

    @Test func unsupportedLanguageFallsBackToFrench() {
        #expect(LanguageManager.resolve(stored: nil, preferredLanguages: ["de"]) == .fr)
        #expect(LanguageManager.resolve(stored: nil, preferredLanguages: []) == .fr)
    }

    @Test func firstSupportedPreferredLanguageWins() {
        #expect(LanguageManager.resolve(stored: nil, preferredLanguages: ["de", "ar-DZ"]) == .ar)
        #expect(LanguageManager.resolve(stored: nil, preferredLanguages: ["de", "en", "ar"]) == .en)
    }

    @Test func storedChoiceBeatsDevice() {
        #expect(LanguageManager.resolve(stored: "en", preferredLanguages: ["ar-DZ"]) == .en)
    }

    @Test func unknownStoredValueIsIgnored() {
        #expect(LanguageManager.resolve(stored: "de", preferredLanguages: ["ar"]) == .ar)
    }

    @Test @MainActor func selectingStoresTheChoice() throws {
        let defaults = try #require(UserDefaults(suiteName: "LanguageResolutionTests"))
        defaults.removePersistentDomain(forName: "LanguageResolutionTests")
        let manager = LanguageManager(defaults: defaults, preferredLanguages: ["fr-FR"])
        var changes: [AppLanguage] = []
        manager.onChange = { changes.append($0) }

        manager.select(.ar)

        #expect(manager.language == .ar)
        #expect(changes == [.ar])
        #expect(LanguageManager(defaults: defaults, preferredLanguages: ["en"]).language == .ar)
    }

    @Test @MainActor func everyKeyIsTranslatedInEveryLanguage() throws {
        let defaults = try #require(UserDefaults(suiteName: "LanguageKeysTests"))
        let manager = LanguageManager(defaults: defaults, preferredLanguages: ["fr"])
        for language in AppLanguage.allCases {
            manager.select(language)
            for key in L10nKey.allCases {
                #expect(manager.string(key) != key.rawValue, "\(key.rawValue) is missing in \(language.rawValue)")
            }
        }
        defaults.removePersistentDomain(forName: "LanguageKeysTests")
    }
}
