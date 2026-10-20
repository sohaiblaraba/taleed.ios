import Foundation
import TaleedAPI

/// What a report is about: exactly one target (slice C, Reporting).
enum ReportTarget: Equatable, Sendable {
    case listing(id: String)
    /// The member's `id`, not the username.
    case member(id: String)
    case conversation(id: String)
}

/// `POST /reports` (screens.md §2 G19; slice C, Reporting), shared by the listing, the profile and
/// the conversation.
@MainActor
protocol ReportsApi: AnyObject {
    /// `reason`: a `value` of the catalog's `reportReasons`. `evidenceKeys`: up to 3 `report_evidence` uploads.
    func report(_ target: ReportTarget, reason: String, details: String?, evidenceKeys: [String]) async throws(ApiError)
}

extension GeneratedTaleedApi: ReportsApi {
    func report(_ target: ReportTarget, reason: String, details: String?, evidenceKeys: [String]) async throws(ApiError) {
        // The catalog value the member picked, never another category. The sheet only lists reasons
        // this build can send (`Catalog`), so this fails only on a programming error.
        guard let reportReason = ReportReason(rawValue: reason), reportReason != .unknownDefaultOpenApi else {
            let issue = ApiFieldIssue(path: "body.reason", message: "reason unknown to this build")
            throw .failed(ApiFailure(status: 400, code: .invalidRequest, issues: [issue]))
        }
        let request = ReportCreate(target, reason: reportReason, details: details, evidenceKeys: evidenceKeys)
        #if DEBUG
        try ReportDebugFailures.fail(.send)
        #endif
        // A repeat after a lost answer says `already_reported`, which the sheet treats as sent.
        try await caller.call(.write) { try await SafetyAPI.createReport(reportCreate: request, apiConfiguration: $0) }
    }
}

extension ReportCreate {
    /// The request body: exactly one of `listingId`, `memberId` and `conversationId`, and no
    /// `evidenceKeys` when there is no screenshot.
    init(_ target: ReportTarget, reason: ReportReason, details: String?, evidenceKeys: [String]) {
        var listingId: String?
        var memberId: String?
        var conversationId: String?
        switch target {
        case let .listing(id): listingId = id
        case let .member(id): memberId = id
        case let .conversation(id): conversationId = id
        }
        self.init(
            listingId: listingId, memberId: memberId, conversationId: conversationId,
            reason: reason,
            details: details, evidenceKeys: evidenceKeys.isEmpty ? nil : evidenceKeys
        )
    }
}

#if DEBUG
/// `-TaleedDebugReport offline`: the first `POST /reports` fails offline before it is sent (nothing is
/// written). `limit`: it answers `429` with an hour to wait. `upload`: the first screenshot upload
/// fails offline. Several: `offline,upload`. For screenshots of the sheet's error states (screens.md §0.6).
enum ReportDebugFailures {
    enum Point {
        case send, upload
    }

    /// Debug only, and touched from the main actor in practice.
    nonisolated(unsafe) private static var used: Set<String> = []

    static func fail(_ point: Point) throws(ApiError) {
        let modes = Set((UserDefaults.standard.string(forKey: "TaleedDebugReport") ?? "").split(separator: ",").map(String.init))
        let candidates = point == .send ? ["offline", "limit"] : ["upload"]
        guard let mode = candidates.first(where: { modes.contains($0) && !used.contains($0) }) else { return }
        used.insert(mode)
        throw mode == "limit" ? .rateLimited(retryAfter: 3600) : .network
    }
}
#endif
