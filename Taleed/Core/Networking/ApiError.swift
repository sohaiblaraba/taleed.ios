import Foundation
import TaleedAPI

/// The API's error codes, generated from the contract (api-guide.md, Error codes). A code added after
/// this build decodes as `.unknownDefaultOpenApi`; `ApiError` then keeps its name in `.unknown`.
typealias ApiErrorCode = ErrorCode

/// One invalid field of an `invalid_request` answer (`issues[]`).
struct ApiFieldIssue: Equatable, Sendable {
    /// Where: `body.title`, `query.cursor`, `path.id`.
    let path: String
    /// English, for developers. Never show it: show the app's text for the field.
    let message: String

    /// The field without its location: `title` for `body.title`, `delivery.communeId` for
    /// `body.delivery.communeId`.
    var field: String {
        guard let dot = path.firstIndex(of: ".") else { return path }
        return String(path[path.index(after: dot)...])
    }
}

/// A failed call whose body names a code the app knows, other than the ones `ApiError` has a case for.
struct ApiFailure: Equatable, Sendable {
    let status: Int
    let code: ApiErrorCode
    /// `invalid_request` (and `offer_out_of_range`, `promo_invalid`, `payment_method_unavailable`):
    /// the fields to highlight.
    var issues: [ApiFieldIssue] = []
    /// `carrier_error` only: the carrier's explanation, shown to the seller as it is.
    var detail: String?
    /// `listing_unavailable` from checkout only: the member's own order awaiting payment holds the
    /// goods. Open that order instead of saying the item is gone (slice F).
    var orderId: String?
}

/// A failed API call, by what the app does about it.
///
/// Parsed from the body `{"error":{"code","message","issues","detail","retryAfter","orderId"}}`. A body
/// that is not JSON, or a code the app does not know, falls back to the HTTP status: a 4xx means
/// "this could not be done", a 5xx "something went wrong, try again" (api-guide.md, Errors).
enum ApiError: Error, Equatable, Sendable {
    /// `401 unauthorized`: the token is missing or no longer valid. Handled globally (sign-out).
    case unauthorized
    /// `403 banned`: the account is suspended. Handled globally (suspended screen).
    case banned
    /// `401 invalid_credentials`: wrong email or password at sign-in.
    case invalidCredentials
    /// `429`: too many requests. `retryAfter` is in seconds, from the body or the `Retry-After` header.
    case rateLimited(retryAfter: Int?)
    /// No answer: offline, timeout, or the connection dropped.
    case network
    /// A 5xx answer without a code the app handles by name (`internal`, a proxy's HTML page).
    case server(status: Int)
    /// A code the app knows: `not_found`, `forbidden`, `invalid_request`, `offer_pending`… Switch on
    /// `code`.
    case failed(ApiFailure)
    /// A 4xx whose code the app does not know (added after this build), or a bare 4xx from the proxy.
    case unknown(status: Int, code: String?)

    // MARK: Reading

    /// The API's code when the answer named one the app knows.
    var code: ApiErrorCode? {
        switch self {
        case .unauthorized: .unauthorized
        case .banned: .banned
        case .invalidCredentials: .invalidCredentials
        case .rateLimited: .rateLimited
        case let .failed(failure): failure.code
        case .network, .server, .unknown: nil
        }
    }

    /// The HTTP status, nil when no answer came.
    var status: Int? {
        switch self {
        case .unauthorized, .invalidCredentials: 401
        case .banned: 403
        case .rateLimited: 429
        case .network: nil
        case let .server(status), let .unknown(status, _): status
        case let .failed(failure): failure.status
        }
    }

    /// The invalid fields of an `invalid_request`, empty otherwise.
    var issues: [ApiFieldIssue] {
        if case let .failed(failure) = self { return failure.issues }
        return []
    }

    /// The issue of one field, by its path (`body.title`).
    func issue(at path: String) -> ApiFieldIssue? {
        issues.first { $0.path == path }
    }

    /// `listing_unavailable` from checkout: the member's own order that holds the goods.
    var orderId: String? {
        if case let .failed(failure) = self { return failure.orderId }
        return nil
    }

    /// `carrier_error`: the carrier's explanation.
    var detail: String? {
        if case let .failed(failure) = self { return failure.detail }
        return nil
    }

    /// The seconds to wait on a `429`, when the answer said.
    var retryAfter: Int? {
        if case let .rateLimited(seconds) = self { return seconds }
        return nil
    }

    /// `404 not_found`: show the "no longer available" state.
    var isNotFound: Bool { code == .notFound }

    /// A read may be repeated after this error (api-guide.md, Retrying): no answer, or a 5xx without
    /// a code that says the feature is off. Never true for a 4xx.
    var isTransient: Bool {
        switch self {
        case .network, .server: true
        case let .failed(failure):
            // `shipping_unavailable` and `payment_unavailable` say "retry"; `carrier_error` and
            // `feature_disabled` do not change on a retry.
            failure.code == .shippingUnavailable || failure.code == .paymentUnavailable
        default: false
        }
    }

    /// A `400` whose cursor the API no longer accepts: start the list again from its first page.
    var isInvalidCursor: Bool {
        code == .invalidRequest && issues.contains { $0.path == "query.cursor" }
    }

    // MARK: Parsing

    /// Maps an HTTP status and response body to an `ApiError`.
    /// A status of `-1` or below means that no answer came (the generated client's convention).
    /// `retryAfterHeader` is the `Retry-After` header, used when the body has no `retryAfter`.
    static func from(status: Int, body: Data?, retryAfterHeader: String? = nil) -> ApiError {
        guard status > 0 else { return .network }
        let detail = body.flatMap { try? JSONDecoder().decode(Envelope.self, from: $0).error }
        let headerSeconds = retryAfterHeader.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        if let detail, let code = ApiErrorCode(rawValue: detail.code), code != .unknownDefaultOpenApi {
            return from(code: code, status: status, detail: detail, retryAfterHeader: headerSeconds)
        }

        switch status {
        case 429: return .rateLimited(retryAfter: headerSeconds)
        case 500..<600: return .server(status: status)
        default: return .unknown(status: status, code: detail?.code)
        }
    }

    private static func from(code: ApiErrorCode, status: Int, detail: EnvelopeDetail, retryAfterHeader: Int?) -> ApiError {
        switch code {
        case .unauthorized: .unauthorized
        case .banned: .banned
        case .invalidCredentials: .invalidCredentials
        case .rateLimited: .rateLimited(retryAfter: detail.retryAfter ?? retryAfterHeader)
        case ._internal: .server(status: status)
        default:
            .failed(ApiFailure(
                status: status,
                code: code,
                issues: (detail.issues ?? []).map { ApiFieldIssue(path: $0.path, message: $0.message) },
                detail: detail.detail,
                orderId: detail.orderId
            ))
        }
    }

    /// Maps an error that the generated client throws.
    static func from(_ error: ErrorResponse) -> ApiError {
        switch error {
        case let .error(status, data, response, underlying):
            if underlying is URLError { return .network }
            if underlying is DecodingError {
                // A successful answer that does not decode; the generated client reports it as 400.
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? status
                return .unknown(status: httpStatus, code: nil)
            }
            let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            return from(status: status, body: data, retryAfterHeader: retryAfter)
        }
    }
}

/// Reads the error code as a string, so that a code the app does not know keeps its name.
private struct Envelope: Decodable {
    let error: EnvelopeDetail
}

private struct EnvelopeDetail: Decodable {
    let code: String
    let retryAfter: Int?
    let issues: [EnvelopeIssue]?
    let detail: String?
    let orderId: String?
}

private struct EnvelopeIssue: Decodable {
    let path: String
    let message: String
}
