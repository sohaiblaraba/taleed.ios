import Foundation
import TaleedAPI

/// A failed API call, by what the app does about it.
///
/// Parsed from the body `{"error":{"code","message","issues"}}`. A body that is not JSON, or a
/// code the app does not handle by name, falls back to the HTTP status (api-guide.md, Errors).
enum ApiError: Error, Equatable, Sendable {
    /// `401 unauthorized`: the token is missing or no longer valid.
    case unauthorized
    /// `403 banned`: the account is suspended.
    case banned
    /// `401 invalid_credentials`: wrong email or password at sign-in.
    case invalidCredentials
    /// `429`: too many requests. `retryAfter` is in seconds when the API gives it.
    case rateLimited(retryAfter: Int?)
    /// No answer: offline, timeout, or the connection dropped.
    case network
    /// A 5xx answer whose code the app does not handle by name.
    case server(status: Int)
    /// Any other failure. `code` is the API's error code when the body had one.
    case unknown(status: Int, code: String?)

    /// Maps an HTTP status and response body to an `ApiError`.
    /// A status of `-1` or below means that no answer came (the generated client's convention).
    static func from(status: Int, body: Data?) -> ApiError {
        guard status > 0 else { return .network }
        let detail = body.flatMap { try? JSONDecoder().decode(Envelope.self, from: $0).error }

        switch detail.flatMap({ ErrorCode(rawValue: $0.code) }) {
        case .unauthorized: return .unauthorized
        case .banned: return .banned
        case .invalidCredentials: return .invalidCredentials
        case .rateLimited: return .rateLimited(retryAfter: detail?.retryAfter)
        default: break
        }

        switch status {
        case 429: return .rateLimited(retryAfter: nil)
        case 500..<600: return .server(status: status)
        default: return .unknown(status: status, code: detail?.code)
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
            return from(status: status, body: data)
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
}
