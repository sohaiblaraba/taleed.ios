import Foundation
@testable import Taleed
import Testing

struct ApiErrorTests {
    private func body(_ code: String, extra: String = "") -> Data {
        Data(#"{"error":{"code":"\#(code)","message":"Developer text."\#(extra)}}"#.utf8)
    }

    @Test func unauthorized() {
        #expect(ApiError.from(status: 401, body: body("unauthorized")) == .unauthorized)
    }

    @Test func banned() {
        #expect(ApiError.from(status: 403, body: body("banned")) == .banned)
    }

    @Test func invalidCredentials() {
        #expect(ApiError.from(status: 401, body: body("invalid_credentials")) == .invalidCredentials)
    }

    @Test func rateLimitedKeepsRetryAfter() {
        let error = ApiError.from(status: 429, body: body("rate_limited", extra: #","retryAfter":30"#))
        #expect(error == .rateLimited(retryAfter: 30))
    }

    @Test func unknownCodeWith4xxFallsBackToStatus() {
        #expect(ApiError.from(status: 409, body: body("brand_new_code")) == .unknown(status: 409, code: "brand_new_code"))
    }

    @Test func unknownCodeWith5xxIsServer() {
        #expect(ApiError.from(status: 503, body: body("brand_new_code")) == .server(status: 503))
    }

    @Test func nonJSON503IsServer() {
        let html = Data("<html><body>503 Service Unavailable</body></html>".utf8)
        #expect(ApiError.from(status: 503, body: html) == .server(status: 503))
    }

    @Test func bare403IsNotBanned() {
        #expect(ApiError.from(status: 403, body: nil) == .unknown(status: 403, code: nil))
    }

    @Test func noAnswerIsNetwork() {
        #expect(ApiError.from(status: -1, body: nil) == .network)
    }
}
