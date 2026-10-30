@testable import Taleed
import Testing

@MainActor
private final class FakeCrashReporter: CrashReporter {
    private(set) var userIDs: [String?] = []
    private(set) var values: [String: String] = [:]

    func setUserID(_ id: String?) { userIDs.append(id) }
    func setCustomValue(_ value: String, forKey key: String) { values[key] = value }
}

@MainActor
struct CrashReportingTests {
    private let reporter = FakeCrashReporter()

    /// The member's `id` after a sign-in or at launch with a session; cleared at sign-out and deletion.
    @Test func theUserIdFollowsTheSession() {
        let crashes = CrashReporting(reporter: reporter)
        crashes.sessionDidStart(memberId: "cmmember1")
        crashes.sessionDidEnd()
        crashes.sessionDidStart(memberId: "cmmember2")
        crashes.sessionDidEnd()
        #expect(reporter.userIDs == ["cmmember1", nil, "cmmember2", nil])
    }

    /// Only non-personal keys: the language and the appearance.
    @Test func theCustomKeysAreNotPersonal() {
        let crashes = CrashReporting(reporter: reporter)
        crashes.languageDidChange(.ar)
        crashes.appearanceDidChange(.dark)
        #expect(reporter.values == ["app_language": "ar", "app_appearance": "dark"])
    }

    /// A build without Firebase: nothing happens, nothing crashes.
    @Test func withoutFirebaseNothingHappens() {
        let crashes = CrashReporting(reporter: nil)
        crashes.sessionDidStart(memberId: "cmmember1")
        crashes.sessionDidEnd()
        crashes.languageDidChange(.fr)
    }
}
