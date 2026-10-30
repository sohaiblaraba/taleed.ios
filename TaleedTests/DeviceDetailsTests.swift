import Foundation
@testable import Taleed
import TaleedAPI
import Testing

struct DeviceDetailsTests {
    /// The body of `POST /devices` (slice J): the token, `ios`, the language and the five details.
    @Test func theRegistrationCarriesTheFiveDetails() throws {
        let details = DeviceDetails(appVersion: "20261002", appBuild: "20261003", osVersion: "26.0", deviceModel: "iPhone18,2")
        let body = DeviceRegistration(token: "fcm", language: .ar, details: details)
        #expect(body.token == "fcm")
        #expect(body.platform == .ios)
        #expect(body.locale == .ar)
        #expect(body.appVersion == "20261002")
        #expect(body.appBuild == "20261003")
        #expect(body.osVersion == "26.0")
        #expect(body.deviceManufacturer == "Apple")
        #expect(body.deviceModel == "iPhone18,2")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: String]
        #expect(json == ["token": "fcm", "platform": "ios", "locale": "ar", "appVersion": "20261002", "appBuild": "20261003",
                         "osVersion": "26.0", "deviceManufacturer": "Apple", "deviceModel": "iPhone18,2"])
    }

    /// Trimmed; empty is not sent (it would keep the stored value anyway); cut to the API's limit, which
    /// answers `400` above it.
    @Test func detailsAreTrimmedCutAndLeftOutWhenEmpty() {
        let details = DeviceDetails(appVersion: "  1.2.0 ", appBuild: " ", osVersion: String(repeating: "9", count: 40),
                                    deviceManufacturer: "Apple", deviceModel: String(repeating: "m", count: 70))
        let body = DeviceRegistration(token: "fcm", language: .fr, details: details)
        #expect(body.appVersion == "1.2.0")
        #expect(body.appBuild == nil)
        #expect(body.osVersion?.count == 32)
        #expect(body.deviceModel?.count == 64)
    }

    /// `utsname.machine` (on the simulator, the model it simulates): never empty, never the Mac's `arm64`.
    @Test func theModelIsTheHardwareIdentifier() {
        let model = DeviceDetails.machine()
        #expect(!model.isEmpty)
        #expect(model.hasPrefix("iPhone") || model.hasPrefix("iPad"))
    }

    @MainActor
    @Test func theCurrentDetailsComeFromTheBuildAndTheDevice() {
        let environment = AppEnvironment(apiBaseURL: URL(string: "http://localhost")!, appVersion: "20261002",
                                         buildNumber: "20261002", appStoreID: nil)
        let details = DeviceDetails.current(environment: environment)
        #expect(details.appVersion == "20261002")
        #expect(details.appBuild == "20261002")
        #expect(details.deviceManufacturer == "Apple")
        #expect(!details.osVersion.isEmpty)
    }
}
