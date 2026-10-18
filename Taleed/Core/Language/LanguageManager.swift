import Foundation
import Observation
import SwiftUI

/// The languages of the app. The raw value is the code sent as `Accept-Language`.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case fr
    case ar
    case en

    static let fallback: AppLanguage = .fr

    var id: String { rawValue }

    /// The language's name in that language, as the language picker shows it.
    var nativeName: String {
        switch self {
        case .fr: "Français"
        case .ar: "العربية"
        case .en: "English"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var layoutDirection: LayoutDirection { self == .ar ? .rightToLeft : .leftToRight }
}

/// Resolves, stores and applies the app language.
///
/// A choice made in Settings is stored and wins. Otherwise the app uses the first language of the
/// device's preferred list that it supports, and French when it supports none.
@MainActor
@Observable
final class LanguageManager {
    private(set) var language: AppLanguage

    /// Called after the language changes, to update `Accept-Language` and reload server labels.
    @ObservationIgnored var onChange: ((AppLanguage) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var bundle: Bundle
    static let storageKey = "app_language"

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        let language = Self.resolve(
            stored: defaults.string(forKey: Self.storageKey),
            preferredLanguages: preferredLanguages
        )
        self.language = language
        self.bundle = Self.bundle(for: language)
    }

    /// The stored choice when there is one, otherwise the first supported language of the device's
    /// preferred list (`[de, ar-DZ]` → `ar`), otherwise French.
    nonisolated static func resolve(stored: String?, preferredLanguages: [String]) -> AppLanguage {
        if let stored, let language = AppLanguage(rawValue: stored) { return language }
        return preferredLanguages.lazy.compactMap(language(fromTag:)).first ?? .fallback
    }

    /// The language of a BCP 47 tag such as `ar-DZ` or `en_GB`, when the app has it.
    nonisolated static func language(fromTag tag: String) -> AppLanguage? {
        let code = tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        return code.flatMap(AppLanguage.init(rawValue:))
    }

    /// Stores the choice and applies it at once, without a restart.
    func select(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.storageKey)
        guard language != self.language else { return }
        bundle = Self.bundle(for: language)
        self.language = language
        onChange?(language)
    }

    /// The app string for `key` in the app language, whatever the device language is.
    func string(_ key: L10nKey) -> String {
        // Reading `language` makes views that call this update when it changes.
        _ = language
        return bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

extension View {
    /// Applies the app language's locale and layout direction. Use it at the root and on every
    /// sheet or full-screen cover, because presented views do not inherit the layout direction.
    func appLanguage(_ language: AppLanguage) -> some View {
        environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
    }
}
