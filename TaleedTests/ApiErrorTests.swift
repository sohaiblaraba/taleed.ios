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

    @Test func knownCodeKeepsItsDetails() {
        let error = ApiError.from(status: 400, body: body("invalid_request",
                                                          extra: #","issues":[{"path":"body.title","message":"Too short."}]"#))
        #expect(error.code == .invalidRequest)
        #expect(error.issues == [ApiFieldIssue(path: "body.title", message: "Too short.")])
        #expect(error.issue(at: "body.title")?.field == "title")
        #expect(error.status == 400)
    }

    @Test func listingUnavailableCarriesTheOrder() {
        let error = ApiError.from(status: 409, body: body("listing_unavailable", extra: #","orderId":"o1""#))
        #expect(error.code == .listingUnavailable)
        #expect(error.orderId == "o1")
    }

    @Test func carrierErrorCarriesTheDetail() {
        let error = ApiError.from(status: 502, body: body("carrier_error", extra: #","detail":"Wilaya not served""#))
        #expect(error.code == .carrierError)
        #expect(error.detail == "Wilaya not served")
        #expect(!error.isTransient)
    }

    @Test func notFound() {
        #expect(ApiError.from(status: 404, body: body("not_found")).isNotFound)
    }

    @Test func internalIsServer() {
        #expect(ApiError.from(status: 500, body: body("internal")) == .server(status: 500))
    }

    @Test func rateLimitedReadsTheHeaderWhenTheBodyHasNoWait() {
        #expect(ApiError.from(status: 429, body: body("rate_limited"), retryAfterHeader: "162") == .rateLimited(retryAfter: 162))
        #expect(ApiError.from(status: 429, body: nil, retryAfterHeader: " 30 ") == .rateLimited(retryAfter: 30))
        #expect(ApiError.from(status: 429, body: Data("<html>".utf8)) == .rateLimited(retryAfter: nil))
    }

    @Test func invalidCursor() {
        let error = ApiError.from(status: 400, body: body("invalid_request",
                                                          extra: #","issues":[{"path":"query.cursor","message":"Bad."}]"#))
        #expect(error.isInvalidCursor)
        #expect(!ApiError.from(status: 400, body: body("invalid_request")).isInvalidCursor)
    }

    @Test func transientErrorsAreTheOnesToRetry() {
        #expect(ApiError.network.isTransient)
        #expect(ApiError.server(status: 503).isTransient)
        #expect(ApiError.failed(ApiFailure(status: 503, code: .shippingUnavailable)).isTransient)
        #expect(!ApiError.failed(ApiFailure(status: 503, code: .featureDisabled)).isTransient)
        #expect(!ApiError.unknown(status: 409, code: nil).isTransient)
        #expect(!ApiError.rateLimited(retryAfter: 5).isTransient)
        #expect(!ApiError.unauthorized.isTransient)
    }
}
