import SwiftUI

extension AppLanguage {
    /// The app language of a locale (`ar-DZ` → Arabic), French when the app does not have it.
    init(locale: Locale) {
        self = locale.language.languageCode.flatMap { AppLanguage(rawValue: $0.identifier) } ?? .fallback
    }
}

/// App strings for design-system components, in the language of the `\.locale` environment value.
/// Components use it for their own fixed copy and accessibility labels, so they work in previews
/// without a `LanguageManager`.
enum DesignSystemStrings {
    static func string(_ key: L10nKey, language: AppLanguage) -> String {
        LanguageManager.localizedString(key, language: language)
    }

    static func string(_ key: L10nKey, locale: Locale) -> String {
        string(key, language: AppLanguage(locale: locale))
    }

    /// A string with `%d` / `%@` arguments, starting in the language's direction (`inParagraphDirection`).
    static func format(_ key: L10nKey, locale: Locale, _ arguments: CVarArg...) -> String {
        String(format: string(key, locale: locale), locale: locale, arguments: arguments)
            .inParagraphDirection(of: AppLanguage(locale: locale))
    }
}
