import Foundation

/// `GET /catalog`: the reference data and its labels, in the language it was fetched in
/// (api-guide.md, Languages). Never copy these labels into string files (architecture rule 4).
///
/// Codes (`value`) stay strings, so that a value added after this build is kept and shown with the
/// catalog's label, or left out where the app needs to know it.
struct Catalog: Codable, Equatable, Sendable {
    /// Top-level categories, in display order.
    var categories: [CatalogCategory]
    var conditions: [CatalogCondition]
    var sorts: [CatalogOption]
    /// Every wilaya, by code (16 is Algiers).
    var wilayas: [CatalogWilaya]
    var reportReasons: [CatalogOption]
    var disputeReasons: [CatalogDisputeReason]
    var payoutMethods: [CatalogOption]

    /// The condition of an API code, nil for a code the catalog does not list (no badge).
    func condition(_ code: String?) -> CatalogCondition? {
        code.flatMap { code in conditions.first { $0.value == code } }
    }

    func wilaya(_ id: Int?) -> CatalogWilaya? {
        id.flatMap { id in wilayas.first { $0.id == id } }
    }

    /// The category of a slug, top-level or subcategory.
    func category(slug: String) -> CatalogCategory? {
        for category in categories {
            if category.slug == slug { return category }
            if let child = category.children.first(where: { $0.slug == slug }) { return child }
        }
        return nil
    }

    /// The top-level category of a subcategory; nil for a top-level or unknown slug.
    func parentCategory(of slug: String) -> CatalogCategory? {
        categories.first { category in category.children.contains { $0.slug == slug } }
    }
}

/// A category. Top-level ones have subcategories; listings are filed under those.
struct CatalogCategory: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    /// Used in filters (`category=`) and website URLs.
    let slug: String
    let name: String
    var children: [CatalogCategory] = []
}

/// A listing condition with its full label (listing screen, sell form, filters) and the short label of
/// card chips (slice F).
struct CatalogCondition: Codable, Equatable, Hashable, Sendable {
    /// `NEW_WITH_TAGS`, `VERY_GOOD`…
    let value: String
    let label: String
    let shortLabel: String
}

/// A code and its label: sorts, report reasons, payout methods.
struct CatalogOption: Codable, Equatable, Hashable, Sendable {
    let value: String
    let label: String
}

struct CatalogDisputeReason: Codable, Equatable, Hashable, Sendable {
    let value: String
    let label: String
    /// The dispute form needs at least one photo for this reason.
    let needsEvidence: Bool
}

struct CatalogWilaya: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
}
