import Foundation
import TaleedAPI

/// How a call may be repeated after a failure (api-guide.md, Retrying).
enum CallKind: Sendable {
    /// Every `GET`, and the actions the slices list as free to repeat (`POST /checkout/quote`,
    /// `POST /…/sync`, `POST /notifications/read`, the `clientId` actions). Repeated after no answer or
    /// a 5xx, 1, 2 and 4 s apart, before the error reaches the screen (which then offers "Retry").
    case read
    /// Every other action. Never repeated automatically: it may have happened anyway, so the screen
    /// reloads and offers a retry button.
    case write
}

/// Runs the generated client's calls for the app: gives them the configured `TaleedAPIAPIConfiguration`,
/// maps their errors to `ApiError`, reports a rejected token, retries reads with backoff, and keeps
/// automatic requests quiet while the API asks to wait (`429`).
///
/// Wrappers call it as `try await caller.call { try await ListingsAPI.getListing(id: id, apiConfiguration: $0) }`.
@MainActor
final class ApiCaller {
    let session: ApiSession

    /// Called when the API rejects the token that a request carried (`401 unauthorized`), with that
    /// token. `SessionManager` sets it to sign out globally.
    var onUnauthorized: ((String) -> Void)?

    /// The waits between attempts of a read. Three retries: 1, 2 and 4 seconds.
    var retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
    /// Replaced in tests.
    var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    var now: () -> Date = { Date() }

    /// Set by a `429`: until then, requests the app makes on its own (`automatic: true`) fail at once
    /// instead of hitting the API again (api-guide.md, Rate limits: never retry in a loop).
    private(set) var rateLimitedUntil: Date?

    /// The wait when a `429` does not say how long: Cloudflare's page has no `Retry-After`.
    static let defaultRateLimitWait: TimeInterval = 5

    init(session: ApiSession) {
        self.session = session
    }

    /// Runs `operation` with the shared configuration.
    /// - Parameters:
    ///   - kind: `.read` retries transient failures; `.write` never repeats.
    ///   - automatic: true for a request the member did not ask for (refresh on foreground, polling):
    ///     it is not sent while a `429` asks to wait.
    func call<T: Sendable>(
        _ kind: CallKind = .read,
        automatic: Bool = false,
        _ operation: (TaleedAPIAPIConfiguration) async throws -> T
    ) async throws(ApiError) -> T {
        try await call(kind, automatic: automatic, configuration: session.configuration, operation)
    }

    /// Runs `operation` with another configuration, such as `session.uploadConfiguration()`.
    func call<T: Sendable>(
        _ kind: CallKind,
        automatic: Bool = false,
        configuration: TaleedAPIAPIConfiguration,
        _ operation: (TaleedAPIAPIConfiguration) async throws -> T
    ) async throws(ApiError) -> T {
        if automatic, let until = rateLimitedUntil {
            let remaining = until.timeIntervalSince(now())
            if remaining > 0 { throw .rateLimited(retryAfter: Int(remaining.rounded(.up))) }
            rateLimitedUntil = nil
        }

        var attempt = 0
        while true {
            let sentToken = configuration.customHeaders["Authorization"].map { String($0.dropFirst("Bearer ".count)) }
            let apiError: ApiError
            do {
                return try await operation(configuration)
            } catch let error as ErrorResponse {
                apiError = ApiError.from(error)
            } catch {
                // The generated client only throws `ErrorResponse`; anything else (cancellation) got no answer.
                apiError = .network
            }
            record(apiError, sentToken: sentToken)
            guard kind == .read, apiError.isTransient, attempt < retryDelays.count, !Task.isCancelled else {
                throw apiError
            }
            do {
                try await sleep(retryDelays[attempt])
            } catch {
                throw apiError
            }
            attempt += 1
        }
    }

    private func record(_ error: ApiError, sentToken: String?) {
        switch error {
        case .unauthorized:
            if let sentToken { onUnauthorized?(sentToken) }
        case let .rateLimited(seconds):
            let wait = seconds.map(TimeInterval.init) ?? Self.defaultRateLimitWait
            rateLimitedUntil = now().addingTimeInterval(wait)
        default:
            break
        }
    }
}
