import Foundation
@testable import Taleed
import TaleedAPI

private typealias ApiError = Taleed.ApiError
import Testing

/// Retries, the rejected token and the rate-limit pause (api-guide.md, Retrying and Rate limits).
@MainActor
struct ApiCallerTests {
    private let session = ApiSession(environment: .fixture(), language: .fr, configuration: .init())
    private let caller: ApiCaller
    private let sleeps = Recorder<Duration>()

    init() {
        caller = ApiCaller(session: session)
        let sleeps = self.sleeps
        caller.sleep = { duration in await sleeps.append(duration) }
    }

    private static let offline = ErrorResponse.error(-1, nil, nil, URLError(.notConnectedToInternet))

    private static func answer(_ status: Int, _ code: String? = nil, retryAfter: Int? = nil) -> ErrorResponse {
        let body = code.map { code in
            let wait = retryAfter.map { #","retryAfter":\#($0)"# } ?? ""
            return Data(#"{"error":{"code":"\#(code)","message":"x"\#(wait)}}"#.utf8)
        }
        return .error(status, body, nil, NSError(domain: "HTTP", code: status))
    }

    @Test func readsRetryAfterNoAnswerThenSucceed() async throws {
        var attempts = 0
        let value = try await caller.call(.read) { _ in
            attempts += 1
            if attempts < 3 { throw Self.offline }
            return 42
        }
        #expect(value == 42)
        #expect(attempts == 3)
        #expect(await sleeps.values == [.seconds(1), .seconds(2)])
    }

    @Test func readsGiveUpAfterThreeRetries() async {
        var attempts = 0
        await #expect(throws: ApiError.server(status: 503)) {
            try await caller.call(.read) { _ -> Int in
                attempts += 1
                throw Self.answer(503)
            }
        }
        #expect(attempts == 4)
        #expect(await sleeps.values == [.seconds(1), .seconds(2), .seconds(4)])
    }

    @Test func writesNeverRepeat() async {
        var attempts = 0
        await #expect(throws: ApiError.network) {
            try await caller.call(.write) { _ -> Int in
                attempts += 1
                throw Self.offline
            }
        }
        #expect(attempts == 1)
    }

    @Test func clientErrorsAreNotRetried() async {
        var attempts = 0
        await #expect(throws: ApiError.failed(ApiFailure(status: 404, code: .notFound))) {
            try await caller.call(.read) { _ -> Int in
                attempts += 1
                throw Self.answer(404, "not_found")
            }
        }
        #expect(attempts == 1)
    }

    @Test func rejectedTokenIsReported() async {
        session.setToken("old")
        var rejected: [String] = []
        caller.onUnauthorized = { rejected.append($0) }
        await #expect(throws: ApiError.unauthorized) {
            try await caller.call { _ -> Int in throw Self.answer(401, "unauthorized") }
        }
        #expect(rejected == ["old"])
    }

    @Test func automaticRequestsWaitOutARateLimit() async throws {
        let start = Date(timeIntervalSince1970: 1000)
        var now = start
        caller.now = { now }
        await #expect(throws: ApiError.rateLimited(retryAfter: 30)) {
            try await caller.call { _ -> Int in throw Self.answer(429, "rate_limited", retryAfter: 30) }
        }
        var attempts = 0
        // Automatic: not sent while the API asks to wait.
        await #expect(throws: ApiError.rateLimited(retryAfter: 20)) {
            now = start.addingTimeInterval(10)
            return try await caller.call(automatic: true) { _ -> Int in
                attempts += 1
                return 1
            }
        }
        #expect(attempts == 0)
        // Asked by the member: sent.
        _ = try await caller.call { _ -> Int in
            attempts += 1
            return 1
        }
        #expect(attempts == 1)
        // After the wait, automatic requests go again.
        now = start.addingTimeInterval(31)
        _ = try await caller.call(automatic: true) { _ -> Int in
            attempts += 1
            return 1
        }
        #expect(attempts == 2)
    }
}

/// Collects values from `@Sendable` closures.
actor Recorder<Value: Sendable> {
    private(set) var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }
}
