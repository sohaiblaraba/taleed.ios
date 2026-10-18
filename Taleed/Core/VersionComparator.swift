import Foundation

/// Compares semantic versions numerically: `1.10.0` is newer than `1.9.0`.
/// Missing parts count as `0` (`1.0` equals `1.0.0`), and so do parts that are not numbers.
enum VersionComparator {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parts(lhs)
        let right = parts(rhs)
        for index in 0..<max(left.count, right.count) {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart < rightPart { return .orderedAscending }
            if leftPart > rightPart { return .orderedDescending }
        }
        return .orderedSame
    }

    /// True when `version` is older than `minimum`.
    static func isVersion(_ version: String, below minimum: String) -> Bool {
        compare(version, minimum) == .orderedAscending
    }

    private static func parts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: .whitespaces)
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { part in
                // "2-beta" counts as 2; anything without leading digits counts as 0.
                Int(part.prefix { $0.isASCII && $0.isNumber }) ?? 0
            }
    }
}
