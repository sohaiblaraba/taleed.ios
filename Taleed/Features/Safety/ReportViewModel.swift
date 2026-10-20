import Foundation
import Observation
import UIKit

/// The report sheet (screens.md §2 G19, §7 G19; slice C, Reporting), shared by the listing, the
/// profile and the conversation: a reason from the catalog, optional details (2 000 characters at
/// most) and up to 3 screenshots (`report_evidence` uploads), then `POST /reports`.
@MainActor
@Observable
final class ReportViewModel {
    /// A screenshot of the report: uploading, uploaded (with its key) or failed.
    struct Evidence: Identifiable, Equatable {
        let id = UUID()
        var preview: UIImage?
        var key: String?
        var error: ApiError?

        var isUploading: Bool { key == nil && error == nil }
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
    var reason: String?
    var details: String = "" {
        didSet {
            if details.utf16.count > Self.maxDetailsLength {
                details = details.prefix(utf16Units: Self.maxDetailsLength)
            }
        }
    }
    private(set) var evidence: [Evidence] = []
    private(set) var isSending = false
    /// The last failure, shown above the button.
    private(set) var error: ApiError?

    @ObservationIgnored private let api: ReportsApi
    @ObservationIgnored private let upload: (Data) async throws(ApiError) -> UploadedPhoto

    init(target: ReportTarget, api: ReportsApi, upload: @escaping (Data) async throws(ApiError) -> UploadedPhoto) {
        self.target = target
        self.api = api
        self.upload = upload
    }

    var canAddEvidence: Bool { evidence.count < Self.maxEvidence && !isSending }

    var isUploading: Bool { evidence.contains(where: \.isUploading) }

    /// A reason is required; uploads must have finished (a failed one is left out, as on the website).
    var canSubmit: Bool { reason != nil && !isSending && !isUploading }

    /// Uploads a picked screenshot. Returns once the upload ended.
    func addEvidence(_ data: Data) async {
        guard canAddEvidence else { return }
        let item = Evidence(preview: Self.preview(from: data))
        evidence.append(item)
        do {
            let uploaded = try await upload(data)
            update(item.id) { $0.key = uploaded.key }
        } catch {
            update(item.id) { $0.error = error }
        }
    }

    /// A picked photo the library could not hand over (an iCloud photo offline, an unreadable file):
    /// a failed tile the member can remove, with the reason under the screenshots.
    func addUnreadableEvidence() {
        guard canAddEvidence else { return }
        evidence.append(Evidence(preview: nil, error: .failed(ApiFailure(status: 415, code: .unsupportedMediaType))))
    }

    func removeEvidence(_ id: UUID) {
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
