import Foundation
import Observation
import UIKit

/// The sell form (screens.md §2 G7 and §7 G7; slice B, Selling; website `sell/page.tsx`,
/// `listing-form.tsx`, `photo-uploader.tsx`): up to 5 photos, each uploaded as soon as it is picked
/// (`listing_photo`) with a retry per photo, the fields checked on the device, then `POST /listings`.
/// There are no drafts (§7 G7): the form lives as long as the Sell tab, and starts over after publishing
/// or when another member signs in.
@MainActor
@Observable
final class SellViewModel {
    var form = SellForm() {
        didSet { recheckShownErrors(from: oldValue) }
    }

    private(set) var photos: [SellPhoto] = []
    /// The errors on screen, by field: set when the member publishes, then updated as they fix each one.
    private(set) var fieldErrors: [SellField: SellFieldError] = [:]
    private(set) var isPublishing = false
    /// Why the last publish failed, above the button (offline, rate limit, "check the fields"…).
    private(set) var publishError: ApiError?
    /// Changes at each refused publish, so the screen scrolls to the first error.
    private(set) var refusals = 0
    /// Changes each time the form starts over, so the screen goes back to its top.
    private(set) var resets = 0

    static let maxPhotos = SellLimits.photosMax

    /// Set on the edit form: the listing as loaded, what Save compares with.
    private(set) var baseline: ListingEditBaseline?

    @ObservationIgnored private let api: SellApi?
    @ObservationIgnored private let editApi: EditListingApi?
    @ObservationIgnored private let upload: (Data) async throws(ApiError) -> UploadedPhoto
    /// Fetches lists again after the API refused a choice from them, so that picking again offers
    /// what it knows now.
    @ObservationIgnored private let refreshLists: (Set<SellReferenceList>) async -> Void

    init(api: SellApi, upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto, wilayaId: Int? = nil,
         refreshLists: @escaping (Set<SellReferenceList>) async -> Void = { _ in }) {
        self.api = api
        editApi = nil
        self.upload = upload
        self.refreshLists = refreshLists
        form.wilayaId = wilayaId
    }

    /// The edit form, filled from the listing (slice B, Editing). A listing without a wilaya shows the
    /// member's, as on the website, and saves it.
    init(editing listing: ListingDetail, brands: [CatalogBrand], memberWilayaId: Int?, api: EditListingApi,
         upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto,
         refreshLists: @escaping (Set<SellReferenceList>) async -> Void = { _ in }) {
        self.api = nil
        editApi = api
        self.upload = upload
        self.refreshLists = refreshLists
        let saved = SellForm.saved(listing, brands: brands)
        baseline = ListingEditBaseline(listingId: listing.id, form: saved, photoIds: listing.photos.map(\.id))
        var form = saved
        if form.wilayaId == nil { form.wilayaId = memberWilayaId }
        self.form = form
        photos = listing.photos.prefix(Self.maxPhotos).map { SellPhoto(kept: $0) }
    }

    var isEditing: Bool { baseline != nil }

    // MARK: State

    var remainingPhotoSlots: Int { max(0, Self.maxPhotos - photos.count) }

    var canAddPhotos: Bool { remainingPhotoSlots > 0 && !isPublishing }

    var isUploading: Bool { photos.contains(where: \.isUploading) }

    /// Publishing waits for the uploads (the button stays off meanwhile; each photo shows its spinner).
    var canPublish: Bool { !isPublishing && !isUploading }

    /// The first field with an error, in screen order (where the screen scrolls).
    var firstErrorField: SellField? {
        SellField.allCases.first { fieldErrors[$0] != nil }
    }

    private var uploadedKeys: [String] { photos.compactMap(\.key) }

    /// The photos the request sends, in display order (new uploads and, when editing, kept photos).
    private var photoReferences: [ListingPhotoRef] { photos.compactMap(\.reference) }

    // MARK: Photos

    /// Adds picked photos (HEIC included: `PhotoUploadService` converts them) and uploads each one at once.
    /// Photos beyond the 5 are dropped. Returns once every upload ended.
    func addPhotos(_ picked: [Data]) async {
        guard !isPublishing else { return }
        let added = picked.prefix(remainingPhotoSlots).map { SellPhoto(data: $0) }
        guard !added.isEmpty else { return }
        photos.append(contentsOf: added)
        photosDidChange()
        await withTaskGroup(of: Void.self) { group in
            for photo in added {
                group.addTask { await self.loadPreview(photo.id) }
                group.addTask { await self.send(photo.id) }
            }
        }
    }

    /// Sends a failed photo again, when that may work.
    func retry(_ id: SellPhoto.ID) async {
        guard let photo = photos.first(where: { $0.id == id }), photo.canRetry else { return }
        await send(id)
    }

    func remove(_ id: SellPhoto.ID) {
        photos.removeAll { $0.id == id }
        photosDidChange()
    }

    /// Moves a photo first: it becomes the cover (the website's "Définir comme couverture").
    func makeCover(_ id: SellPhoto.ID) {
        guard let index = photos.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let photo = photos.remove(at: index)
        photos.insert(photo, at: 0)
    }

    private func send(_ id: SellPhoto.ID) async {
        guard let data = photos.first(where: { $0.id == id })?.data else { return }
        update(id) { $0.upload = .uploading }
        let result: SellPhotoUpload
        do {
            #if DEBUG
            try Self.debugFailure(.upload)
            #endif
            result = .uploaded(try await upload(data))
        } catch {
            result = .failed(error)
        }
        // Removed meanwhile: nothing to update (an unused upload does no harm).
        update(id) { $0.upload = result }
        photosDidChange()
    }

    /// A small preview from the picked data, made off the main thread.
    private func loadPreview(_ id: SellPhoto.ID) async {
        guard let data = photos.first(where: { $0.id == id })?.data, let image = UIImage(data: data),
              image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(1, 400 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let preview = await image.byPreparingThumbnail(ofSize: size) ?? image
        update(id) { $0.preview = preview }
    }

    private func update(_ id: SellPhoto.ID, _ change: (inout SellPhoto) -> Void) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        change(&photos[index])
    }

    // MARK: Publishing

    /// Checks the form and publishes it. Returns the new listing's id, or nil when a field or the API
    /// refused it (the errors are then on screen).
    func publish() async -> String? {
        guard let api, canPublish else { return nil }
        publishError = nil
        guard checkFields(), let submission = form.submission(photoKeys: uploadedKeys) else { return nil }
        isPublishing = true
        var staleLists: Set<SellReferenceList> = []
        do {
            #if DEBUG
            try Self.debugFailure(.publish)
            #endif
            let listingId = try await api.createListing(submission)
            isPublishing = false
            return listingId
        } catch {
            publishError = error
            if error.code == .invalidRequest { staleLists = applyIssues(error.issues) }
        }
        isPublishing = false
        if !staleLists.isEmpty { await refreshLists(staleLists) }
        return nil
    }

    /// Checks every field on the device and shows the errors. False (and the screen scrolls to the
    /// first error) when one fails.
    private func checkFields() -> Bool {
        var errors = form.errors(photoCount: photoReferences.count)
        if photos.contains(where: { $0.error != nil }) { errors[.photos] = .photoUploadFailed }
        fieldErrors = errors
        guard errors.isEmpty else {
            refusals += 1
            return false
        }
        return true
    }

    /// The API's field errors (slice B, Field errors): highlight the fields, and upload again each photo
    /// whose key it refused (expired, or used by another listing). Returns the lists to fetch again.
    private func applyIssues(_ issues: [ApiFieldIssue]) -> Set<SellReferenceList> {
        applyIssues(SellForm.mapping(of: issues))
    }

    private func applyIssues(_ mapping: SellForm.IssueMapping) -> Set<SellReferenceList> {
        fieldErrors = mapping.errors
        refusals += 1
        let photoIds = sentPhotoIds
        let rejected = mapping.rejectedPhotos.compactMap { photoIds.indices.contains($0) ? photoIds[$0] : nil }
        for id in rejected where photos.first(where: { $0.id == id })?.data != nil {
            Task { await self.send(id) }
        }
        return mapping.staleLists
    }

    /// The photos sent, in the order of `photos[]` in the request.
    private var sentPhotoIds: [SellPhoto.ID] { photos.filter { $0.reference != nil }.map(\.id) }

    /// Starts over (after publishing, or for another member). `wilayaId`: the member's wilaya.
    func reset(wilayaId: Int?) {
        photos = []
        fieldErrors = [:]
        publishError = nil
        form = SellForm()
        form.wilayaId = wilayaId
        resets += 1
    }

    /// The member's wilaya arrived after the form opened (`GET /me`): prefill it unless one was chosen.
    func memberWilayaDidLoad(_ wilayaId: Int?) {
        guard form.wilayaId == nil, let wilayaId else { return }
        form.wilayaId = wilayaId
    }

    // MARK: Errors as the member fixes them

    /// A field's error is checked again when the member changes that field: it goes once the value
    /// passes (or, for "pick again", once another value is picked). Untouched fields keep theirs, and
    /// no new error appears before the next publish.
    private func recheckShownErrors(from old: SellForm) {
        guard !fieldErrors.isEmpty else { return }
        let hadCategoryError = fieldErrors[.category] != nil
        let changed: [SellField: Bool] = [
            .title: old.title != form.title,
            .description: old.description != form.description,
            .category: old.parentCategoryId != form.parentCategoryId,
            .subcategory: old.categoryId != form.categoryId,
            .brand: old.brand != form.brand,
            .size: old.size != form.size,
            .condition: old.condition != form.condition,
            .price: old.priceText != form.priceText,
            .wilaya: old.wilayaId != form.wilayaId,
        ]
        let current = form.errors(photoCount: photoReferences.count)
        for (field, didChange) in changed where didChange && fieldErrors[field] != nil {
            fieldErrors[field] = current[field]
        }
        // The category was missing and is now picked: the subcategory still is.
        if hadCategoryError, changed[.category] == true, fieldErrors[.category] == nil,
           let missing = current[.subcategory] {
            fieldErrors[.subcategory] = missing
        }
    }

    private func photosDidChange() {
        guard fieldErrors[.photos] != nil else { return }
        if photos.contains(where: { $0.error != nil }) {
            fieldErrors[.photos] = .photoUploadFailed
        } else if photoReferences.isEmpty, !isUploading {
            fieldErrors[.photos] = .photoRequired
        } else {
            fieldErrors[.photos] = nil
        }
    }

    // MARK: Debug

    #if DEBUG
    private enum DebugStep { case upload, publish }

    /// `-TaleedDebugSell upload` fails the first photo upload as if offline, `upload-refused` as too
    /// large (`413`), `publish` the first publish (screenshots of the offline states, of the retry and of
    /// a photo to remove, since the simulator has no airplane mode).
    private enum DebugFailure: String {
        case upload, publish
        case uploadRefused = "upload-refused"

        var step: DebugStep { self == .publish ? .publish : .upload }
        var error: ApiError { self == .uploadRefused ? .failed(ApiFailure(status: 413, code: .fileTooLarge)) : .network }
    }

    private static var debugFailed: Set<String> = []

    private static func debugFailure(_ step: DebugStep) throws(ApiError) {
        guard let failure = UserDefaults.standard.string(forKey: "TaleedDebugSell").flatMap(DebugFailure.init(rawValue:)),
              failure.step == step, !debugFailed.contains(failure.rawValue) else { return }
        debugFailed.insert(failure.rawValue)
        throw failure.error
    }
    #endif
}

// MARK: - Editing (G8)

extension SellViewModel {
    /// "Enregistrer les modifications": checks the form, then `PATCH /listings/{id}` with only what changed
    /// (slice B, Editing). Nothing changed still sends the request: the answer is the listing as it is
    /// now, or why it can no longer change.
    func save() async -> ListingSaveOutcome {
        guard let editApi, let baseline, canPublish else { return .refused }
        publishError = nil
        guard checkFields(), var changes = form.changes(since: baseline.form, photoCount: photoReferences.count) else {
            return .refused
        }
        changes.photos = baseline.photoChanges(photoReferences)
        isPublishing = true
        defer { isPublishing = false }
        do {
            #if DEBUG
            try Self.debugFailure(.publish)
            #endif
            return .saved(try await editApi.updateListing(id: baseline.listingId, changes: changes))
        } catch {
            switch error.code {
            case .listingLocked, .forbidden:
                return .cannotEdit(error)
            case .notFound:
                return .gone
            case .invalidRequest:
                let mapping = SellForm.mapping(of: error.issues)
                if mapping.listingChanged { return .listingChanged }
                publishError = error
                let staleLists = applyIssues(mapping)
                if !staleLists.isEmpty {
                    isPublishing = false
                    await refreshLists(staleLists)
                }
                return .refused
            default:
                publishError = error
                return .refused
            }
        }
    }

    /// The listing again, after it was edited somewhere else: its photos as they are now, then the
    /// member's new uploads; its values, except the fields the member changed.
    func reloadListing(_ listing: ListingDetail, brands: [CatalogBrand]) {
        guard let old = baseline, old.listingId == listing.id else { return }
        let saved = SellForm.saved(listing, brands: brands)
        let shownWilaya = form.wilayaId
        var reloaded = SellForm.reloaded(edited: form, old: old.form, fresh: saved)
        // Still without a wilaya: the member's stays, as when the form opened.
        if reloaded.wilayaId == nil { reloaded.wilayaId = shownWilaya }
        form = reloaded
        baseline = ListingEditBaseline(listingId: listing.id, form: saved, photoIds: listing.photos.map(\.id))
        let added = photos.filter { if case .kept = $0.upload { false } else { true } }
        photos = Array((listing.photos.map { SellPhoto(kept: $0) } + added).prefix(Self.maxPhotos))
        fieldErrors = [:]
        publishError = nil
    }
}
