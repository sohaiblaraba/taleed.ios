import Foundation
import Observation
import TaleedAPI
import UIKit

/// Up to 4 evidence photos of a dispute (`dispute_evidence` uploads), each uploaded as soon as it is
/// picked (slice D, Opening a dispute). Shared by the dispute form and the thread's composer.
@MainActor
@Observable
final class EvidencePhotos {
    /// A photo: uploading, uploaded (with its key) or failed.
    struct Item: Identifiable, Equatable {
        let id = UUID()
        var preview: UIImage?
        var key: String?
        var error: ApiError?

        var isUploading: Bool { key == nil && error == nil }
    }

    /// `DisputeCreate.photoKeysRule` and `DisputeMessageCreate.photoKeysRule`.
    static let maxCount = DisputeCreate.photoKeysRule.maxItems ?? 4

    private(set) var items: [Item] = []

    @ObservationIgnored private let upload: (Data) async throws(ApiError) -> UploadedPhoto

    init(upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto) {
        self.upload = upload
    }

    var remaining: Int { max(0, Self.maxCount - items.count) }
    var isUploading: Bool { items.contains(where: \.isUploading) }
    /// The keys of the photos that uploaded; a failed one is left out, as on the website.
    var keys: [String] { items.compactMap(\.key) }
    var firstError: ApiError? { items.first(where: { $0.error != nil })?.error }

    /// Uploads a picked photo. Returns once the upload ended.
    func add(_ data: Data) async {
        guard remaining > 0 else { return }
        let item = Item(preview: Self.preview(from: data))
        items.append(item)
        do {
            let uploaded = try await upload(data)
            update(item.id) { $0.key = uploaded.key }
        } catch {
            update(item.id) { $0.error = error }
        }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func removeAll() {
        items = []
    }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private static func preview(from data: Data) -> UIImage? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, 192 / max(image.size.width, image.size.height))
        return image.preparingThumbnail(of: CGSize(width: image.size.width * scale, height: image.size.height * scale))
    }
}

/// The dispute form (screens.md §2 G12 screen 4 and §7 G12; website `order-actions.tsx`): a reason
/// from `GET /catalog` (default `NOT_RECEIVED`), a description of 10 to 2 000 characters, and up to 4
/// photos, at least one when the reason `needsEvidence`. "Ouvrir le litige" stays disabled until all
/// of it holds and no photo is uploading.
@MainActor
@Observable
final class DisputeFormViewModel {
    /// What `submit` did.
    enum Outcome: Equatable {
        /// `201`: the thread to open.
        case opened(DisputeInfo)
        /// The order moved on (`dispute_exists`, `invalid_state`, `not_found`, `forbidden`): close the
        /// form and reload the order, which has the dispute or its new buttons.
        case orderChanged(ApiError)
        /// Shown in the form; the member can send again.
        case failed(ApiError)
    }

    /// `DisputeCreate.descriptionRule`, counted in UTF-16 units as the API counts.
    static let minDescription = DisputeCreate.descriptionRule.minLength ?? 10
    static let maxDescription = DisputeCreate.descriptionRule.maxLength ?? 2000
    /// The website's default reason.
    static let defaultReason = "NOT_RECEIVED"

    let orderId: String
    var reason: String?
    var description: String = "" {
        didSet {
            if description.utf16.count > Self.maxDescription {
                description = description.prefix(utf16Units: Self.maxDescription)
            }
        }
    }
    let photos: EvidencePhotos
    private(set) var isSending = false
    /// The last failure, shown above the button.
    private(set) var error: ApiError?

    @ObservationIgnored private let api: OrdersApi

    init(orderId: String, api: OrdersApi, upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto) {
        self.orderId = orderId
        self.api = api
        photos = EvidencePhotos(upload: upload)
    }

    /// Picks the website's default reason once the catalog's reasons are known.
    func setReasons(_ reasons: [DisputeReasonOption]) {
        guard reason == nil || !reasons.contains(where: { $0.value == reason }) else { return }
        reason = reasons.first(where: { $0.value == Self.defaultReason })?.value ?? reasons.first?.value
    }

    func needsEvidence(in reasons: [DisputeReasonOption]) -> Bool {
        reasons.first(where: { $0.value == reason })?.needsEvidence ?? false
    }

    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isDescriptionLongEnough: Bool { trimmedDescription.utf16.count >= Self.minDescription }

    /// The website's rule: a reason, 10 characters, a photo when the reason needs one, nothing uploading.
    func canSubmit(reasons: [DisputeReasonOption]) -> Bool {
        guard reason != nil, !isSending, !photos.isUploading, isDescriptionLongEnough else { return false }
        return !needsEvidence(in: reasons) || !photos.keys.isEmpty
    }

    /// The field the API refused (`invalid_request` on `body.description`), for its message.
    var descriptionRejected: Bool {
        error?.issue(at: "body.description") != nil
    }

    func submit(reasons: [DisputeReasonOption]) async -> Outcome? {
        guard canSubmit(reasons: reasons), let reason else { return nil }
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            let dispute = try await api.openDispute(orderId: orderId, reason: reason, description: trimmedDescription,
                                                    photoKeys: photos.keys)
            return .opened(dispute)
        } catch {
            switch error.code {
            case .disputeExists, .invalidState, .notFound, .forbidden:
                return .orderChanged(error)
            default:
                self.error = error
                return .failed(error)
            }
        }
    }
}

/// The dispute thread (screens.md §2 G12 screen 5 and G13 screen 4; slice D "The thread", "The seller's
/// answer"; website `dispute-thread.tsx`): `GET /disputes/{id}`, the whole thread oldest first, and,
/// while `canPost`, a composer for some text (2 000 characters at most), up to 4 photos, or both.
/// Posting is not idempotent: the button is disabled while it sends, and a failed post reloads the
/// thread before the member tries again. While `canRespond`, the seller accepts or contests the claim.
@MainActor
@Observable
final class DisputeThreadViewModel {
    let disputeId: String
    private(set) var dispute: DisputeInfo?
    private(set) var loadError: ApiError?
    private(set) var isLoading = false
    private(set) var isSending = false
    /// A failure to tell in a toast.
    var notice: ApiError?
    /// A success to tell in a toast.
    var success: L10nKey?
    /// The answer to the claim being sent.
    private(set) var answering: DisputeAnswerChoice?
    var draft: String = "" {
        didSet {
            if draft.utf16.count > Self.maxBody { draft = draft.prefix(utf16Units: Self.maxBody) }
        }
    }
    let photos: EvidencePhotos
    /// Moves when a message was posted, to scroll to it.
    private(set) var postedCount = 0

    /// `DisputeMessageCreate.bodyRule`.
    static let maxBody = DisputeMessageCreate.bodyRule.maxLength ?? 2000

    @ObservationIgnored private let api: OrdersApi

    init(disputeId: String, api: OrdersApi, upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto) {
        self.disputeId = disputeId
        self.api = api
        photos = EvidencePhotos(upload: upload)
    }

    var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Some text or a photo, nothing uploading, nothing sending.
    var canSend: Bool {
        dispute?.canPost == true && !isSending && answering == nil && !photos.isUploading && (!trimmedDraft.isEmpty || !photos.keys.isEmpty)
    }

    func loadIfNeeded() async {
        guard dispute == nil, loadError == nil, !isLoading else { return }
        await load()
    }

    func retry() async {
        loadError = nil
        await load()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            dispute = try await api.dispute(id: disputeId, automatic: false)
            loadError = nil
        } catch {
            loadError = error
        }
    }

    /// Pull-to-refresh and the foreground.
    func reload(automatic: Bool = false) async {
        guard dispute != nil else {
            await load()
            return
        }
        do {
            dispute = try await api.dispute(id: disputeId, automatic: automatic)
        } catch {
            if error.isNotFound {
                dispute = nil
                loadError = error
            } else if !automatic {
                notice = error
            }
        }
    }

    /// "Accepter la réclamation" (once confirmed) or "Contester", while `canRespond`: the dispute as it
    /// now is (refunded, or under review). An answer that no longer applies reloads the thread.
    func answer(_ answer: DisputeAnswerChoice) async {
        guard dispute?.canRespond == true, answering == nil, !isSending else { return }
        answering = answer
        defer { answering = nil }
        do {
            dispute = try await api.respondToDispute(disputeId: disputeId, answer: answer)
            success = answer == .accept ? .disputesAcceptDone : .disputesContestDone
        } catch {
            notice = error
            await reload(automatic: true)
        }
    }

    /// "Envoyer". Returns true when the message was posted.
    @discardableResult
    func send() async -> Bool {
        guard canSend else { return false }
        isSending = true
        defer { isSending = false }
        let body = trimmedDraft
        do {
            dispute = try await api.postDisputeMessage(disputeId: disputeId, body: body.isEmpty ? nil : body,
                                                       photoKeys: photos.keys)
            draft = ""
            photos.removeAll()
            postedCount += 1
            return true
        } catch {
            notice = error
            // It may have been posted anyway, or the dispute was resolved meanwhile (`invalid_state`):
            // the thread as it is now, before the member tries again (slice D, Retrying).
            await reload(automatic: true)
            return false
        }
    }
}

/// The review form (screens.md §2 G12 screen 6; website review dialog): stars from 1 to 5, 5 by
/// default, and an optional comment of 1 000 characters at most (`POST /orders/{id}/review`).
@MainActor
@Observable
final class ReviewFormViewModel {
    enum Outcome: Equatable {
        /// `201`: the order with `myReview`.
        case reviewed(OrderDetailInfo)
        /// `already_reviewed`, `invalid_state`, `not_found`: close and reload the order.
        case orderChanged(ApiError)
        case failed(ApiError)
    }

    static let minRating = ReviewCreate.ratingRule.minimum ?? 1
    static let maxRating = ReviewCreate.ratingRule.maximum ?? 5
    static let maxComment = ReviewCreate.commentRule.maxLength ?? 1000

    let orderId: String
    var rating: Int = ReviewFormViewModel.maxRating {
        didSet {
            // Only when out of range: setting it again in `didSet` re-enters it under `@Observable`.
            let clamped = min(Self.maxRating, max(Self.minRating, rating))
            if clamped != rating { rating = clamped }
        }
    }
    var comment: String = "" {
        didSet {
            if comment.utf16.count > Self.maxComment { comment = comment.prefix(utf16Units: Self.maxComment) }
        }
    }
    private(set) var isSending = false
    private(set) var error: ApiError?

    @ObservationIgnored private let api: OrdersApi

    init(orderId: String, api: OrdersApi) {
        self.orderId = orderId
        self.api = api
    }

    var canSubmit: Bool { !isSending }

    func submit() async -> Outcome? {
        guard canSubmit else { return nil }
        isSending = true
        error = nil
        defer { isSending = false }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return .reviewed(try await api.review(orderId: orderId, rating: rating, comment: trimmed.isEmpty ? nil : trimmed))
        } catch {
            switch error.code {
            case .alreadyReviewed, .invalidState, .notFound, .forbidden:
                return .orderChanged(error)
            default:
                self.error = error
                return .failed(error)
            }
        }
    }
}
