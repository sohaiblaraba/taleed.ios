import Foundation
import TaleedAPI

/// The call of the sell form (screens.md §2 G7; slice B, Selling). The photos go through
/// `PhotoUploadService` first; the brands and sizes come from `ExploreReferenceStore`.
@MainActor
protocol SellApi: AnyObject {
    /// `POST /listings`: the new listing's id. Sending the same photos again after a lost answer returns
    /// the listing already published (slice B, Publishing).
    func createListing(_ listing: ListingSubmission) async throws(ApiError) -> String
}

/// What `POST /listings` sends, already checked and trimmed by `SellForm`.
struct ListingSubmission: Equatable, Sendable {
    /// What the listing is filed under when it has no catalog brand.
    enum Brand: Equatable, Sendable {
        case catalog(id: String)
        case typed(name: String)
    }

    let title: String
    let description: String
    let price: Int
    /// A subcategory id (`categories[].children[].id`).
    let categoryId: String
    /// The catalog code (`VERY_GOOD`).
    let condition: String
    let brand: Brand?
    let size: String?
    /// Left out: the seller's wilaya.
    let wilayaId: Int?
    /// Upload keys, in display order; the first is the cover.
    let photoKeys: [String]
}

/// A photo of the edit form as `PATCH /listings/{id}` takes it: one the listing has (`{id}`) or a new
/// upload (`{key}`).
enum ListingPhotoRef: Equatable, Sendable {
    case kept(id: String)
    case added(key: String)
}

/// What `PATCH /listings/{id}` sends: only the fields the member changed (slice B, Editing). A field left
/// nil stays as it is.
struct ListingChanges: Equatable, Sendable {
    enum Brand: Equatable, Sendable {
        /// `{}`: the listing has no brand anymore.
        case none
        case catalog(id: String)
        case typed(name: String)
    }

    var title: String?
    var description: String?
    var price: Int?
    /// A subcategory id.
    var categoryId: String?
    var brand: Brand?
    /// `""` removes the size.
    var size: String?
    var condition: String?
    var wilayaId: Int?
    /// The complete new list in display order, or nil to keep the photos as they are.
    var photos: [ListingPhotoRef]?

    var isEmpty: Bool { self == ListingChanges() }
}

/// The calls of the edit form (screens.md §2 G8; slice B, Editing).
@MainActor
protocol EditListingApi: AnyObject {
    /// `GET /listings/{id}` to prefill the form, without counting a view.
    func editableListing(id: String) async throws(ApiError) -> ListingDetail
    /// `PATCH /listings/{id}`: the listing as saved.
    func updateListing(id: String, changes: ListingChanges) async throws(ApiError) -> ListingDetail
}

/// The limits of `POST /listings` (contract `ListingCreate` and `BrandInput` rules), counted after
/// trimming, in UTF-16 units as the API counts.
enum SellLimits {
    static let titleMin = ListingCreate.titleRule.minLength ?? 3
    static let titleMax = ListingCreate.titleRule.maxLength ?? 80
    static let descriptionMin = ListingCreate.descriptionRule.minLength ?? 10
    static let descriptionMax = ListingCreate.descriptionRule.maxLength ?? 2000
    static let priceMin = ListingCreate.priceRule.minimum ?? 100
    static let priceMax = ListingCreate.priceRule.maximum ?? 10_000_000
    static let sizeMax = ListingCreate.sizeRule.maxLength ?? 30
    static let brandNameMax = BrandInput.nameRule.maxLength ?? 60
    static let photosMax = ListingCreate.photosRule.maxItems ?? 5

    /// Digits a price field keeps: one more than the maximum has, so a price over it shows its error.
    static var priceDigitsMax: Int { String(priceMax).count + 1 }

    /// The condition codes this build can send (`ListingCondition`): a code added to the catalog after
    /// this build is not offered.
    static func isSendableCondition(_ code: String) -> Bool {
        guard let condition = ListingCondition(rawValue: code) else { return false }
        return condition != .unknownDefaultOpenApi
    }
}

extension GeneratedTaleedApi: EditListingApi {
    func editableListing(id: String) async throws(ApiError) -> ListingDetail {
        try await listing(id: id, countView: false, automatic: false)
    }

    func updateListing(id: String, changes: ListingChanges) async throws(ApiError) -> ListingDetail {
        let brand: BrandInput? = switch changes.brand {
        case .none?: BrandInput()
        case let .catalog(id)?: BrandInput(id: id)
        case let .typed(name)?: BrandInput(name: name)
        case nil: nil
        }
        let body = ListingUpdate(
            title: changes.title,
            description: changes.description,
            price: changes.price,
            categoryId: changes.categoryId,
            brand: brand,
            size: changes.size,
            condition: changes.condition.map { ListingCondition(rawValue: $0) ?? .unknownDefaultOpenApi },
            wilayaId: changes.wilayaId,
            photos: changes.photos?.map { photo in
                switch photo {
                case let .kept(id): PhotoInput(id: id)
                case let .added(key): PhotoInput(key: key)
                }
            }
        )
        let asOf = ContinuousClock.now
        // A member's action: never repeated on its own (screens.md §0.6). Saving again by hand is safe:
        // the same values change nothing.
        let listing = try await caller.call(.write) {
            try await SellingAPI.updateListing(id: id, listingUpdate: body, apiConfiguration: $0)
        }
        return ListingDetail(listing, asOf: asOf)
    }
}

extension GeneratedTaleedApi: SellApi {
    func createListing(_ listing: ListingSubmission) async throws(ApiError) -> String {
        let brand: BrandInput? = switch listing.brand {
        case let .catalog(id): BrandInput(id: id)
        case let .typed(name): BrandInput(name: name)
        case nil: nil
        }
        let body = ListingCreate(
            title: listing.title,
            description: listing.description,
            price: listing.price,
            categoryId: listing.categoryId,
            brand: brand,
            size: listing.size,
            condition: ListingCondition(rawValue: listing.condition) ?? .unknownDefaultOpenApi,
            wilayaId: listing.wilayaId,
            photos: listing.photoKeys.map { PhotoInput(key: $0) }
        )
        // A member's action: never repeated on its own (screens.md §0.6). Publishing again by hand is
        // safe: the same photos return the listing already published.
        let detail = try await caller.call(.write) {
            try await SellingAPI.createListing(listingCreate: body, apiConfiguration: $0)
        }
        return detail.id
    }
}
