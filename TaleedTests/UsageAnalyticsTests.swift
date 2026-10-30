import Foundation
@testable import Taleed
import Testing

@MainActor
private final class FakeAnalytics: AnalyticsBackend {
    private(set) var collection: [Bool] = []
    private(set) var properties: [String: String?] = [:]

    func setCollectionEnabled(_ isEnabled: Bool) { collection.append(isEnabled) }
    func setUserProperty(_ value: String?, forName name: String) { properties[name] = value }
}

@MainActor
struct UsageAnalyticsTests {
    private let backend = FakeAnalytics()
    private let defaults = UserDefaults(suiteName: "UsageAnalyticsTests.\(UUID().uuidString)")!

    private func analytics(build: Bool = true) -> UsageAnalytics {
        UsageAnalytics(backend: backend, isBuildEnabled: build, buildType: "staging", language: .fr,
                       defaults: defaults)
    }

    /// On by default in a staging or release build; the two properties, no member id.
    @Test func onByDefaultWithTheTwoProperties() {
        let usage = analytics()
        #expect(usage.isSwitchedOn)
        #expect(usage.isCollecting)
        #expect(backend.collection == [true])
        #expect(backend.properties == ["build_type": "staging", "app_language": "fr"])
    }

    /// Debug builds collect nothing, whatever the switch says.
    @Test func debugBuildsCollectNothing() {
        let usage = analytics(build: false)
        #expect(!usage.isCollecting)
        #expect(backend.collection == [false])
    }

    /// The switch applies at once and is kept on the device.
    @Test func theSwitchAppliesAtOnceAndIsKept() {
        let usage = analytics()
        usage.setSwitchedOn(false)
        #expect(backend.collection == [true, false])
        #expect(!usage.isCollecting)
        let next = analytics()
        #expect(!next.isSwitchedOn)
        #expect(backend.collection.last == false)
        next.setSwitchedOn(true)
        #expect(backend.collection.last == true)
    }

    @Test func theLanguagePropertyFollowsTheApp() {
        let usage = analytics()
        usage.languageDidChange(.ar)
        #expect(backend.properties["app_language"] == "ar")
    }
}
