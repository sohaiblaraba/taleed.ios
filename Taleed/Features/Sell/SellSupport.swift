import SwiftUI

/// What the sell form needs besides the shared stores: `POST /listings` and photo uploads. Set once at
/// the root (`AppRootView`).
struct SellDependencies {
    let api: any SellApi
    let uploads: PhotoUploadService
}

private struct SellDependenciesKey: EnvironmentKey {
    static var defaultValue: SellDependencies? { nil }
}

extension EnvironmentValues {
    var sellDependencies: SellDependencies? {
        get { self[SellDependenciesKey.self] }
        set { self[SellDependenciesKey.self] = newValue }
    }
}

/// The size suggestions under the size field (`GET /sizes`): the sizes on sale that contain the typed
/// text, the first 8, without the one already typed.
enum SellSizeSuggestions {
    static let limit = 8

    static func matching(_ typed: String, in sizes: [String]) -> [String] {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = query.isEmpty ? sizes : sizes.filter {
            $0.localizedStandardContains(query) && $0.caseInsensitiveCompare(query) != .orderedSame
        }
        return Array(candidates.prefix(limit))
    }
}

/// The texts of the sell form's field errors.
enum SellMessages {
    static func text(for error: SellFieldError, language: AppLanguage) -> String {
        let locale = language.locale
        func string(_ key: L10nKey) -> String { DesignSystemStrings.string(key, language: language) }
        // The limits grouped as prices are ("2 000", "2.000" in Arabic).
        func number(_ value: Int) -> String { PriceFormatter.number(value, language: language) }
        switch error {
        case .photoRequired: return string(.sellErrorPhotoRequired)
        case .photoUploadFailed: return string(.sellErrorUpload)
        case let .titleLength(min, max):
            return DesignSystemStrings.format(.appSellErrorTitleLength, locale: locale, number(min), number(max))
        case let .descriptionLength(min, max):
            return DesignSystemStrings.format(.appSellErrorDescriptionLength, locale: locale, number(min), number(max))
        case .categoryRequired: return string(.sellErrorCategoryRequired)
        case let .priceRange(min, max):
            return DesignSystemStrings.format(.appSellErrorPriceRange, locale: locale,
                                              PriceFormatter.format(min, language: language),
                                              PriceFormatter.format(max, language: language))
        case .conditionRequired: return string(.appSellErrorConditionRequired)
        case .pickAgain: return string(.appSellErrorPickAgain)
        case let .tooLong(max): return DesignSystemStrings.format(.appSellErrorTooLong, locale: locale, max)
        }
    }
}

extension CatalogCondition {
    /// The full label, as the tags in list rows write it ("Very good condition").
    func fullLabel(in language: AppLanguage) -> String {
        ProductCondition.label(code: value, catalogLabel: label, length: .full, language: language)
    }
}
