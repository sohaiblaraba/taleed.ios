import Foundation
@testable import Taleed
import Testing

struct VersionComparatorTests {
    @Test func comparesPartsNumerically() {
        #expect(VersionComparator.compare("1.10.0", "1.9.0") == .orderedDescending)
    }

    @Test func missingPartsCountAsZero() {
        #expect(VersionComparator.compare("1.0.0", "1.0") == .orderedSame)
    }

    @Test func majorVersionWins() {
        #expect(VersionComparator.compare("2.0.0", "1.99.99") == .orderedDescending)
    }

    @Test func patchVersionCounts() {
        #expect(VersionComparator.compare("1.0.0", "1.0.1") == .orderedAscending)
        #expect(VersionComparator.isVersion("1.0.0", below: "1.0.1"))
    }

    @Test(arguments: ["", "abc", "1..2", "x.y.z", "1.0.0-beta", "🙂"])
    func garbageDoesNotCrashAndCountsAsZero(input: String) {
        _ = VersionComparator.compare(input, "1.0.0")
        _ = VersionComparator.compare("1.0.0", input)
    }

    @Test func garbagePartsAreZero() {
        #expect(VersionComparator.compare("abc", "0") == .orderedSame)
        #expect(VersionComparator.compare("1.x", "1.0") == .orderedSame)
        #expect(VersionComparator.compare("", "0.0.0") == .orderedSame)
    }
}
