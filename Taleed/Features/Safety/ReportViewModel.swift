import Foundation
import Observation
import UIKit

/// The report sheet (screens.md §2 G19, §7 G19; slice C, Reporting), shared by the listing, the
/// profile and the conversation: a reason from the catalog, optional details (2 000 characters at
/// most) and up to 3 screenshots (`report_evidence` uploads), then `POST /reports`.
@MainActor
@Observable
final class ReportViewModel {
    /// A screenshot of the report, from the moment it is picked: waiting for the photo library,
    /// uploading, uploaded (with its key) or failed.
    struct Evidence: Identifiable, Equatable {
        let id = UUID()
        var preview: UIImage?
        var key: String?
        var error: ApiError?
        /// The picked data, kept while sending it again may work (`canRetrySamePhoto`).
        var data: Data?

        /// Picked, not yet uploaded or failed (the library is still handing it over, or it uploads).
        var isUploading: Bool { key == nil && error == nil }
        var isFailed: Bool { error != nil }
        /// Failed in a way sending the same photo again may fix (no connection, 5xx, 429).
        var canRetry: Bool { data != nil && (error?.canRetrySamePhoto ?? false) }
    }

    /// What `submit` did.
    enum Outcome: Equatable {
        /// `204`, or `409 already_reported` (a report is already under review): the thank-you.
        case sent
        /// `404`: the listing, member or conversation is gone.
        case gone
        /// Shown in the sheet; the member can send again.
        case failed(ApiError)
    }

    static let maxEvidence = 3
    /// `ReportCreate.detailsRule`: counted in UTF-16 units, as the API counts.
    static let maxDetailsLength = 2000

    let target: ReportTarget
    var reason: String? {
        didSet { if reason != oldValue { formChanged() } }
    }
    /// Capped by the field itself (`TaleedTextArea.maxLength`), so what is shown is what is sent.
    var details: String = "" {
        didSet { if details != oldValue { formChanged() } }
    }
    private(set) var evidence: [Evidence] = [] {
        didSet { formChanged() }
    }
    private(set) var isSending = false
    /// The last failure, shown above the button until the form changes (an older failure would sit
    /// next to a new one, unrelated).
    private(set) var error: ApiError?

    private func formChanged() {
        if !isSending, error != nil { error = nil }
    }

    @ObservationIgnored private let api: ReportsApi
    @ObservationIgnored private let upload: (Data) async throws(ApiError) -> UploadedPhoto

    init(target: ReportTarget, api: ReportsApi, upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto) {
        self.target = target
        self.api = api
        self.upload = upload
    }

    var canAddEvidence: Bool { evidence.count < Self.maxEvidence && !isSending }

    /// How many more screenshots can be picked.
    var remainingEvidence: Int { max(0, Self.maxEvidence - evidence.count) }

    var isUploading: Bool { evidence.contains(where: \.isUploading) }

    /// A screenshot that could not be attached: Send waits until it is sent again or removed, so none
    /// is left out without a word.
    var hasFailedEvidence: Bool { evidence.contains(where: \.isFailed) }

    var isDetailsTooLong: Bool { details.utf16.count > Self.maxDetailsLength }

    /// A reason is required; every picked screenshot must be attached (none uploading, none failed),
    /// and the details within the limit.
    var canSubmit: Bool { reason != nil && !isSending && !isUploading && !hasFailedEvidence && !isDetailsTooLong }

    /// Adds `count` tiles in their loading state as soon as photos are picked, before the library hands
    /// them over (an iCloud original takes seconds): Send stays off from the first moment. Returns their
    /// ids, to fill with `upload(_:data:)` or `markUnreadable(_:)`.
    func reserveEvidence(_ count: Int) -> [UUID] {
        guard !isSending else { return [] }
        let items = (0..<min(count, remainingEvidence)).map { _ in Evidence() }
        evidence.append(contentsOf: items)
        return items.map(\.id)
    }

    /// Whether the tile is still there (the member may remove it while the library loads it).
    func containsEvidence(_ id: UUID) -> Bool { evidence.contains { $0.id == id } }

    /// Uploads the picked data of a reserved tile. Returns once the upload ended.
    func upload(_ id: UUID, data: Data) async {
        guard containsEvidence(id) else { return }
        let preview = Self.preview(from: data)
        update(id) {
            $0.preview = preview
            $0.data = data
            $0.error = nil
        }
        do {
            let uploaded = try await upload(data)
            update(id) {
                $0.key = uploaded.key
                $0.data = nil
            }
        } catch {
            update(id) {
                $0.error = error
                if !error.canRetrySamePhoto { $0.data = nil }
            }
        }
    }

    /// Sends a failed screenshot again (no connection, server failure, rate limit).
    func retryEvidence(_ id: UUID) async {
        guard !isSending, let item = evidence.first(where: { $0.id == id }), item.canRetry, let data = item.data else { return }
        await upload(id, data: data)
    }

    /// A reserved tile whose photo the library could not hand over (an iCloud photo offline, an
    /// unreadable file): a failed tile the member removes, with the reason under the screenshots.
    func markUnreadable(_ id: UUID) {
        update(id) { $0.error = .failed(ApiFailure(status: 415, code: .unsupportedMediaType)) }
    }

    /// Picks and uploads one screenshot (a reserved tile, then its upload). Returns once the upload ended.
    func addEvidence(_ data: Data) async {
        guard canAddEvidence, let id = reserveEvidence(1).first else { return }
        await upload(id, data: data)
    }

    /// A picked photo the library could not hand over, as a failed tile.
    func addUnreadableEvidence() {
        guard canAddEvidence, let id = reserveEvidence(1).first else { return }
        markUnreadable(id)
    }

    func removeEvidence(_ id: UUID) {
        guard !isSending else { return }
        evidence.removeAll { $0.id == id }
    }

    func submit() async -> Outcome? {
        guard canSubmit, let reason else { return nil }
        isSending = true
        error = nil
        defer { isSending = false }
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await api.report(target, reason: reason, details: trimmed.isEmpty ? nil : trimmed,
                                 evidenceKeys: evidence.compactMap(\.key))
            return .sent
        } catch {
            switch error.code {
            case .alreadyReported: return .sent
            case .notFound: return .gone
            default:
                self.error = error
                return .failed(error)
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Evidence) -> Void) {
        guard let index = evidence.firstIndex(where: { $0.id == id }) else { return }
        change(&evidence[index])
    }

    /// A small preview of the screenshot for the thumbnail.
    private static func preview(from data: Data) -> UIImage? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, 192 / max(image.size.width, image.size.height))
        return image.preparingThumbnail(of: CGSize(width: image.size.width * scale, height: image.size.height * scale))
    }
}
