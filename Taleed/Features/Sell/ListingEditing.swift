import Foundation

/// The listing the edit form was filled from (screens.md §2 G8; slice B, Editing): what Save compares
/// the form with, so that `PATCH /listings/{id}` sends only what the member changed.
struct ListingEditBaseline: Equatable, Sendable {
    let listingId: String
    /// The listing's values as saved (the wilaya may be nil here while the form shows the member's).
    let form: SellForm
    /// The listing's photos, in display order.
    let photoIds: [String]
}

extension SellForm {
    /// The form for a listing as `GET /listings/{id}` returns it. `brands`: `GET /brands`, to find a
    /// catalog brand by its slug (a typed brand, or one not found, shows as its name). The condition is
    /// kept only when this build can send it again.
    static func saved(_ listing: ListingDetail, brands: [CatalogBrand]) -> SellForm {
        var form = SellForm()
        form.title = listing.title
        form.description = listing.description
        form.priceText = String(listing.price)
        if let parentId = listing.category.parentId {
            form.parentCategoryId = parentId
            form.categoryId = listing.category.id
        } else {
            // An older listing filed under a top-level category: kept as it is until the member picks
            // another one, which must then be a subcategory.
            form.parentCategoryId = listing.category.id
            form.topLevelCategoryId = listing.category.id
        }
        form.brand = brand(listing.brand, brands: brands)
        form.size = listing.size ?? ""
        form.condition = listing.condition.flatMap { SellLimits.isSendableCondition($0) ? $0 : nil }
        form.wilayaId = listing.shipsFrom?.id
        return form
    }

    private static func brand(_ brand: ListingBrandRef?, brands: [CatalogBrand]) -> SellBrand {
        guard let brand else { return .none }
        if let slug = brand.slug, let catalogBrand = brands.first(where: { $0.slug == slug }) {
            return .catalog(catalogBrand)
        }
        return .typed(brand.name)
    }

    /// The fields that differ from `baseline`, as `PATCH` sends them (trimmed; `""` removes the size,
    /// `.none` the brand). Nil while a field fails its check.
    func changes(since baseline: SellForm, photoCount: Int) -> ListingChanges? {
        guard errors(photoCount: photoCount).isEmpty, let price else { return nil }
        var changes = ListingChanges()
        if trimmedTitle != baseline.trimmedTitle { changes.title = trimmedTitle }
        if trimmedDescription != baseline.trimmedDescription { changes.description = trimmedDescription }
        if price != baseline.price { changes.price = price }
        if let categoryId, categoryId != baseline.categoryId { changes.categoryId = categoryId }
        if brand != baseline.brand { changes.brand = brandChange }
        if trimmedSize != baseline.trimmedSize { changes.size = trimmedSize }
        if let condition, condition != baseline.condition { changes.condition = condition }
        if let wilayaId, wilayaId != baseline.wilayaId { changes.wilayaId = wilayaId }
        return changes
    }

    /// The brand as `PATCH` replaces it.
    private var brandChange: ListingChanges.Brand {
        switch brand {
        case .none: .none
        case let .catalog(catalogBrand): .catalog(id: catalogBrand.id)
        case let .typed(name): .typed(name: name)
        }
    }

    /// The form after the listing was reloaded (it was edited somewhere else): the fresh values, except
    /// the fields the member had changed from `old`, which keep the member's text or choice.
    static func reloaded(edited: SellForm, old: SellForm, fresh: SellForm) -> SellForm {
        var form = fresh
        if edited.title != old.title { form.title = edited.title }
        if edited.description != old.description { form.description = edited.description }
        if edited.priceText != old.priceText { form.priceText = edited.priceText }
        if edited.parentCategoryId != old.parentCategoryId || edited.categoryId != old.categoryId {
            form.parentCategoryId = edited.parentCategoryId
            form.categoryId = edited.categoryId
        }
        if edited.brand != old.brand { form.brand = edited.brand }
        if edited.size != old.size { form.size = edited.size }
        if edited.condition != old.condition { form.condition = edited.condition }
        if edited.wilayaId != old.wilayaId { form.wilayaId = edited.wilayaId }
        return form
    }
}

extension ListingEditBaseline {
    /// The photos as `PATCH` sends them: nil when they are the listing's, in the same order.
    func photoChanges(_ photos: [ListingPhotoRef]) -> [ListingPhotoRef]? {
        photos == photoIds.map { .kept(id: $0) } ? nil : photos
    }
}

/// Whether the edit form opens for a listing (slice B, What the seller can do; the website's edit page
/// leaves reserved and sold listings for their page).
enum ListingEditability: Equatable, Sendable {
    case editable
    /// Reserved, sold, or a status this build does not know.
    case locked
    /// Not the member's listing: as the website, "not found".
    case notOwner

    init(_ listing: ListingDetail) {
        if !listing.isOwner {
            self = .notOwner
        } else {
            self = ListingDetailActions.OwnerActions(status: listing.status).canEdit ? .editable : .locked
        }
    }
}
