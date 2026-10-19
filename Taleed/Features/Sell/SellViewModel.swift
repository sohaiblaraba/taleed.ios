import Foundation
import Observation
import UIKit

/// The sell form (screens.md §2 G7 and §7 G7; slice B, Selling; website `sell/page.tsx`,
/// `listing-form.tsx`, `photo-uploader.tsx`): up to 5 photos, each uploaded as soon as it is picked
/// (`listing_photo`) with a retry per photo, the fields checked on the device, then `POST /listings`.
/// There are no drafts (§7 G7): the form lives as long as the Sell tab, and starts over after publishing
/// or when another member signs in.
/// Where a photo's upload stands.
enum SellPhotoUpload {
    case uploading
    case uploaded(UploadedPhoto)
    case failed(ApiError)
}

/// A picked photo of the sell form: its preview, what was picked (to send it again), and its upload.
struct SellPhoto: Identifiable {
    let id = UUID()
    var preview: UIImage?
    /// The picked data, kept to upload the photo again (a failure, or a key the API refused).
    let data: Data
    var upload: SellPhotoUpload = .uploading

    var key: String? {
        if case let .uploaded(photo) = upload { return photo.key }
        return nil
    }

    var isUploading: Bool {
        if case .uploading = upload { return true }
        return false
    }

    var error: ApiError? {
        if case let .failed(error) = upload { return error }
        return nil
    }
}

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

    @ObservationIgnored private let api: SellApi
    @ObservationIgnored private let upload: (Data) async throws(ApiError) -> UploadedPhoto

    init(api: SellApi, upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto, wilayaId: Int? = nil) {
        self.api = api
        self.upload = upload
        form.wilayaId = wilayaId
    }

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

    /// Sends a failed photo again.
    func retry(_ id: SellPhoto.ID) async {
        guard let photo = photos.first(where: { $0.id == id }), photo.error != nil else { return }
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
        guard canPublish else { return nil }
        publishError = nil
        var errors = form.errors(photoCount: uploadedKeys.count)
        if photos.contains(where: { $0.error != nil }) { errors[.photos] = .photoUploadFailed }
        fieldErrors = errors
        guard errors.isEmpty, let submission = form.submission(photoKeys: uploadedKeys) else {
            refusals += 1
            return nil
        }
        isPublishing = true
        defer { isPublishing = false }
        do {
            #if DEBUG
            try Self.debugFailure(.publish)
            #endif
            return try await api.createListing(submission)
        } catch {
            publishError = error
            if error.code == .invalidRequest { applyIssues(error.issues) }
            return nil
        }
    }

    /// The API's field errors (slice B, Field errors): highlight the fields, and upload again each photo
    /// whose key it refused (expired, or used by another listing).
    private func applyIssues(_ issues: [ApiFieldIssue]) {
        let mapping = SellForm.mapping(of: issues)
        fieldErrors = mapping.errors
        refusals += 1
        let photoIds = uploadedPhotoIds
        let rejected = mapping.rejectedPhotos.compactMap { photoIds.indices.contains($0) ? photoIds[$0] : nil }
        for id in rejected {
            Task { await self.send(id) }
        }
    }

    /// The photos sent, in the order of `photos[]` in the request.
    private var uploadedPhotoIds: [SellPhoto.ID] { photos.filter { $0.key != nil }.map(\.id) }

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
        let current = form.errors(photoCount: uploadedKeys.count)
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
        } else if uploadedKeys.isEmpty, !isUploading {
            fieldErrors[.photos] = .photoRequired
        } else {
            fieldErrors[.photos] = nil
        }
    }

    // MARK: Debug

    #if DEBUG
    private enum DebugStep: String { case upload, publish }
    private static var debugFailed: Set<String> = []

    /// `-TaleedDebugSell upload` fails the first photo upload as if offline, `publish` the first publish
    /// (screenshots of the offline states and of the retry, since the simulator has no airplane mode).
    private static func debugFailure(_ step: DebugStep) throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugSell") == step.rawValue,
              !debugFailed.contains(step.rawValue) else { return }
        debugFailed.insert(step.rawValue)
        throw .network
    }
    #endif
}
