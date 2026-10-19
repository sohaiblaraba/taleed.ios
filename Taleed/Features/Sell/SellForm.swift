import Foundation

/// A field of the sell form that can show an error, in screen order (Figma "Sell an Item").
enum SellField: String, CaseIterable, Hashable, Sendable {
    case photos, title, description, category, subcategory, brand, size, condition, price, wilaya
}

/// Why a field is refused: on the device before sending, or from the API's `issues`.
enum SellFieldError: Equatable, Sendable {
    /// No photo, or none uploaded (the website's `sell.errorPhotoRequired`).
    case photoRequired
    /// A photo's upload failed: retry or remove it (the website's `sell.errorUpload`).
    case photoUploadFailed
    case titleLength(min: Int, max: Int)
    case descriptionLength(min: Int, max: Int)
    /// No category or no subcategory (the website's `sell.errorCategoryRequired`).
    case categoryRequired
    case priceRange(min: Int, max: Int)
    case conditionRequired
    /// The API no longer knows the chosen value (category, brand, wilaya): pick again (slice B).
    case pickAgain
    /// Longer than the API takes (only from the API: the fields stop at their limits).
    case tooLong(max: Int)
}

/// A reference list the sell form picks from.
enum SellReferenceList: Hashable, Sendable {
    /// `GET /catalog`: categories, conditions, wilayas.
    case catalog
    /// `GET /brands`.
    case brands
}

/// The brand of the listing (the website's brand combobox): none ("Sans marque / Autre"), a catalog
/// brand, or a name the member typed ("Utiliser « … »").
enum SellBrand: Equatable, Sendable {
    case none
    case catalog(CatalogBrand)
    case typed(String)

    /// What the field shows, nil for no brand (the placeholder).
    var displayName: String? {
        switch self {
        case .none: nil
        case let .catalog(brand): brand.name
        case let .typed(name): name
        }
    }

    /// The choice for what the member typed in the brand search: the catalog brand of the same name,
    /// ignoring case (as the API files it), otherwise the typed name. Nil for blank text.
    static func choice(forTyped typed: String, brands: [CatalogBrand]) -> SellBrand? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(utf16Units: SellLimits.brandNameMax)
        guard !name.isEmpty else { return nil }
        if let brand = brands.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return .catalog(brand)
        }
        return .typed(name)
    }

    /// The brands matching the search, as the website filters them (contains, ignoring case; here also
    /// accents), in the catalog's alphabetical order.
    static func matches(_ typed: String, in brands: [CatalogBrand]) -> [CatalogBrand] {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return brands }
        return brands.filter { $0.name.localizedStandardContains(query) }
    }

    /// Whether to offer "Utiliser « … »": some text that names no catalog brand exactly.
    static func offersTypedName(_ typed: String, brands: [CatalogBrand]) -> Bool {
        guard case .typed = choice(forTyped: typed, brands: brands) else { return false }
        return true
    }
}

/// The text fields and choices of the sell form (website `listing-form.tsx`), with its checks. The
/// photos are kept by `SellViewModel`.
struct SellForm: Equatable, Sendable {
    var title = ""
    var description = ""
    /// Digits only (`FilterDraft.priceText`).
    var priceText = ""
    /// The top-level category picked first.
    var parentCategoryId: String?
    /// The subcategory, which the listing is filed under.
    var categoryId: String?
    var brand: SellBrand = .none
    var size = ""
    /// A catalog condition code.
    var condition: String?
    /// The wilaya the item ships from, prefilled from the member's (no "none" choice, as on the website).
    var wilayaId: Int?

    // MARK: Input limits

    /// The fields stop at the API's maximum, as the website's `maxLength` does.
    static func cappedTitle(_ text: String) -> String { text.prefix(utf16Units: SellLimits.titleMax) }
    static func cappedDescription(_ text: String) -> String { text.prefix(utf16Units: SellLimits.descriptionMax) }
    static func cappedSize(_ text: String) -> String { text.prefix(utf16Units: SellLimits.sizeMax) }
    static func cappedBrandSearch(_ text: String) -> String { text.prefix(utf16Units: SellLimits.brandNameMax) }

    // MARK: Values as sent

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedSize: String { size.trimmingCharacters(in: .whitespacesAndNewlines) }
    var price: Int? { Int(priceText) }

    /// Picks a top-level category: the subcategory starts over, as on the website.
    mutating func selectParentCategory(_ id: String) {
        guard id != parentCategoryId else { return }
        parentCategoryId = id
        categoryId = nil
    }

    // MARK: Checks

    /// Every field's error, checked on the device before sending (the API checks formats first and
    /// then reports only those, slice B Field errors). `photoCount`: the photos uploaded.
    func errors(photoCount: Int) -> [SellField: SellFieldError] {
        var errors: [SellField: SellFieldError] = [:]
        if photoCount == 0 { errors[.photos] = .photoRequired }
        if let error = titleError { errors[.title] = error }
        if let error = descriptionError { errors[.description] = error }
        if parentCategoryId == nil {
            errors[.category] = .categoryRequired
        } else if categoryId == nil {
            errors[.subcategory] = .categoryRequired
        }
        if condition == nil { errors[.condition] = .conditionRequired }
        if let error = priceError { errors[.price] = error }
        return errors
    }

    /// Whether `field` passes its own check now (to clear its error as the member fixes it).
    func passes(_ field: SellField, photoCount: Int) -> Bool {
        errors(photoCount: photoCount)[field] == nil
    }

    var titleError: SellFieldError? {
        let length = trimmedTitle.utf16.count
        guard length < SellLimits.titleMin || length > SellLimits.titleMax else { return nil }
        return .titleLength(min: SellLimits.titleMin, max: SellLimits.titleMax)
    }

    var descriptionError: SellFieldError? {
        let length = trimmedDescription.utf16.count
        guard length < SellLimits.descriptionMin || length > SellLimits.descriptionMax else { return nil }
        return .descriptionLength(min: SellLimits.descriptionMin, max: SellLimits.descriptionMax)
    }

    var priceError: SellFieldError? {
        if let price, (SellLimits.priceMin...SellLimits.priceMax).contains(price) { return nil }
        return .priceRange(min: SellLimits.priceMin, max: SellLimits.priceMax)
    }

    /// The request, or nil while a field fails its check. `photoKeys` in display order.
    func submission(photoKeys: [String]) -> ListingSubmission? {
        guard errors(photoCount: photoKeys.count).isEmpty, let price, let categoryId, let condition else { return nil }
        let brand: ListingSubmission.Brand? = switch brand {
        case .none: nil
        case let .catalog(catalogBrand): .catalog(id: catalogBrand.id)
        case let .typed(name): .typed(name: name)
        }
        return ListingSubmission(
            title: trimmedTitle,
            description: trimmedDescription,
            price: price,
            categoryId: categoryId,
            condition: condition,
            brand: brand,
            size: trimmedSize.isEmpty ? nil : trimmedSize,
            wilayaId: wilayaId,
            photoKeys: photoKeys
        )
    }

    // MARK: API issues

    /// What an `invalid_request` from `POST /listings` says, by field (act on the path, never on the
    /// message, slice B Field errors). `rejectedPhotos`: positions of photos to upload again
    /// (`body.photos.<n>.key`).
    struct IssueMapping: Equatable, Sendable {
        var errors: [SellField: SellFieldError] = [:]
        var rejectedPhotos: [Int] = []
        /// Issues on paths the form does not show: say "check the fields" only.
        var hasUnplacedIssues = false
        /// The lists to fetch again before the member picks again: the API no longer knows the chosen
        /// category, wilaya (`GET /catalog`) or brand (`GET /brands`).
        var staleLists: Set<SellReferenceList> = []
    }

    /// The error each `body.<field>` issue shows, and on which field.
    private static let issueFields: [String: (SellField, SellFieldError)] = [
        "title": (.title, .titleLength(min: SellLimits.titleMin, max: SellLimits.titleMax)),
        "description": (.description, .descriptionLength(min: SellLimits.descriptionMin, max: SellLimits.descriptionMax)),
        "price": (.price, .priceRange(min: SellLimits.priceMin, max: SellLimits.priceMax)),
        "categoryId": (.subcategory, .pickAgain),
        "condition": (.condition, .conditionRequired),
        "brand": (.brand, .pickAgain),
        "size": (.size, .tooLong(max: SellLimits.sizeMax)),
        "wilayaId": (.wilaya, .pickAgain),
    ]

    static func mapping(of issues: [ApiFieldIssue]) -> IssueMapping {
        var mapping = IssueMapping()
        for issue in issues {
            let parts = issue.path.split(separator: ".").map(String.init)
            guard parts.first == "body", parts.count >= 2 else {
                mapping.hasUnplacedIssues = true
                continue
            }
            if let (field, error) = issueFields[parts[1]] {
                mapping.errors[field] = error
                if let list = staleList(parts) { mapping.staleLists.insert(list) }
            } else if parts[1] == "photos" {
                if parts.count >= 3, let index = Int(parts[2]) {
                    if !mapping.rejectedPhotos.contains(index) { mapping.rejectedPhotos.append(index) }
                } else {
                    mapping.errors[.photos] = .photoRequired
                }
            } else {
                mapping.hasUnplacedIssues = true
            }
        }
        mapping.rejectedPhotos.sort()
        return mapping
    }

    /// The list behind a refused choice: `body.categoryId`, `body.wilayaId` (the catalog) or
    /// `body.brand.id` (the brands). A typed brand name is not from a list.
    private static func staleList(_ parts: [String]) -> SellReferenceList? {
        switch parts[1] {
        case "categoryId", "wilayaId": .catalog
        case "brand" where parts.count == 2 || parts[2] == "id": .brands
        default: nil
        }
    }
}
