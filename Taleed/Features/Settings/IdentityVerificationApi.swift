import Foundation
import TaleedAPI

/// Where the member's identity verification stands (`GET /me/verification`, slice E "Identity verification").
enum IdentityStatus: Equatable, Sendable {
    /// Nothing sent, or Taleed removed the badge since: the form.
    case none
    /// Under review: no form; the decision comes as a notification.
    case pending
    /// The badge; the legal name is read-only.
    case verified
    /// Refused: the reviewer's note (usually French, at most 300 characters, may be nil) above the form.
    case rejected(note: String?)

    /// The form shows (NONE and REJECTED).
    var acceptsRequest: Bool {
        switch self {
        case .none, .rejected: true
        case .pending, .verified: false
        }
    }

    /// A status this version does not know reads as NONE, the form: the server stays the judge
    /// (`409 invalid_state` reloads the section).
    init(_ verification: IdentityVerification) {
        switch verification.status {
        case .pending: self = .pending
        case .verified: self = .verified
        case .rejected:
            let note = verification.rejectionNote?.trimmingCharacters(in: .whitespacesAndNewlines)
            self = .rejected(note: note?.isEmpty == false ? note : nil)
        case ._none, .unknownDefaultOpenApi: self = .none
        }
    }
}

/// The calls of the identity verification screen (screens.md §2 and §7 G17).
@MainActor
protocol IdentityVerificationApi: AnyObject {
    /// `GET /me/verification`. `automatic`: a refresh the member did not ask for (back in the foreground).
    func verification(automatic: Bool) async throws(ApiError) -> IdentityStatus
    /// `POST /me/verification {documentKey}` → `PENDING`. `409 invalid_state`: already pending or verified
    /// (also the answer to a repeat whose first answer was lost); `400 invalid_request` on
    /// `body.documentKey`: upload the photo again. 5 per day.
    func submitVerification(documentKey: String) async throws(ApiError) -> IdentityStatus
}

extension GeneratedTaleedApi: IdentityVerificationApi {
    func verification(automatic: Bool) async throws(ApiError) -> IdentityStatus {
        #if DEBUG
        try VerificationDebugFailures.fail(.load)
        #endif
        return IdentityStatus(try await caller.call(.read, automatic: automatic) {
            try await VerificationAPI.getVerification(apiConfiguration: $0)
        })
    }

    func submitVerification(documentKey: String) async throws(ApiError) -> IdentityStatus {
        #if DEBUG
        try VerificationDebugFailures.fail(.submit)
        #endif
        let body = IdentityDocument(documentKey: documentKey)
        // Never repeated on its own: after a lost answer, the member's next tap gets `invalid_state`.
        return IdentityStatus(try await caller.call(.write) {
            try await VerificationAPI.submitVerification(identityDocument: body, apiConfiguration: $0)
        })
    }
}

#if DEBUG
/// `-TaleedDebugVerification offline`: the screen's first `GET /me/verification` fails offline (then
/// works). `upload`: the first ID upload fails offline. `limit`: the first send answers `429` with an
/// hour to wait (5 a day). Several: `offline,upload`. For screenshots of the error states (screens.md §0.6).
@MainActor
enum VerificationDebugFailures {
    enum Point: String {
        case load = "offline"
        case upload
        case submit = "limit"
    }

    private static var used: Set<Point> = []

    static func fail(_ point: Point) throws(ApiError) {
        let modes = (UserDefaults.standard.string(forKey: "TaleedDebugVerification") ?? "").split(separator: ",").map(String.init)
        guard modes.contains(point.rawValue), !used.contains(point) else { return }
        used.insert(point)
        throw point == .submit ? .rateLimited(retryAfter: 3600) : .network
    }
}
#endif
