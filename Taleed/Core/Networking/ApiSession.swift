import Foundation
import TaleedAPI

/// Every API call goes through this session. The API ignores cookies, so the app keeps none.
let taleedURLSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    return URLSession(configuration: configuration)
}()

final class TaleedRequestBuilder<T: Sendable>: URLSessionRequestBuilder<T>, @unchecked Sendable {
    override func createURLSession() -> URLSessionProtocol { taleedURLSession }
}

final class TaleedDecodableRequestBuilder<T: Decodable & Sendable>: URLSessionDecodableRequestBuilder<T>, @unchecked Sendable {
    override func createURLSession() -> URLSessionProtocol { taleedURLSession }
}

struct TaleedRequestBuilderFactory: RequestBuilderFactory {
    func getNonDecodableBuilder<T>() -> RequestBuilder<T>.Type { TaleedRequestBuilder<T>.self }
    func getBuilder<T: Decodable>() -> RequestBuilder<T>.Type { TaleedDecodableRequestBuilder<T>.self }
}

/// Holds the token and the language, and sets the headers of api-guide.md on every request:
/// `Accept-Language`, `X-App-Platform`, `X-App-Version` and, once signed in, `Authorization`.
///
/// The state lives in the generated client's configuration, which is thread-safe.
final class ApiSession: Sendable {
    let configuration: TaleedAPIAPIConfiguration
    private let environment: AppEnvironment

    init(
        environment: AppEnvironment,
        language: AppLanguage,
        configuration: TaleedAPIAPIConfiguration = .shared
    ) {
        self.environment = environment
        self.configuration = configuration
        configuration.basePath = environment.apiBaseURL.absoluteString
        configuration.requestBuilderFactory = TaleedRequestBuilderFactory()
        configuration.customHeaders = [
            "Accept-Language": language.rawValue,
            "X-App-Platform": environment.platform,
            "X-App-Version": environment.appVersion,
        ]
    }

    /// The token sent as `Authorization: Bearer <token>`, or nil when signed out.
    var token: String? {
        configuration.customHeaders["Authorization"].map { String($0.dropFirst("Bearer ".count)) }
    }

    func setToken(_ token: String?) {
        configuration.customHeaders["Authorization"] = token.map { "Bearer \($0)" }
    }

    var language: String? { configuration.customHeaders["Accept-Language"] }

    func setLanguage(_ language: AppLanguage) {
        configuration.customHeaders["Accept-Language"] = language.rawValue
    }

    /// A separate configuration with the current headers, for a call that must keep the token
    /// after the session drops it (sign-out).
    func snapshot() -> TaleedAPIAPIConfiguration {
        TaleedAPIAPIConfiguration(
            basePath: configuration.basePath,
            customHeaders: configuration.customHeaders,
            requestBuilderFactory: TaleedRequestBuilderFactory()
        )
    }
}
