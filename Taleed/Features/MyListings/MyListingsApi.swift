import SwiftUI
import TaleedAPI

/// A tab of My listings (screens.md §2 G8): one per status `GET /me/listings` filters on.
enum MyListingsTab: Int, CaseIterable, Hashable, Sendable {
    case active, hidden, reserved, sold

    var status: ListingStatus {
        switch self {
        case .active: .active
        case .hidden: .hidden
        case .reserved: .reserved
        case .sold: .sold
        }
    }

    /// The tab a listing shows in; nil for a draft or a status this build does not know (no tab).
    init?(status: ListingStatus) {
        switch status {
        case .active: self = .active
        case .hidden: self = .hidden
        case .reserved: self = .reserved
        case .sold: self = .sold
        case .draft, .unknown: return nil
        }
    }
}

/// The tab badges: all the member's listings by status, whatever the tab (slice B, The member's listings).
struct MyListingCounts: Equatable, Sendable {
    var active = 0
    var hidden = 0
    var reserved = 0
    var sold = 0

    subscript(tab: MyListingsTab) -> Int {
        get {
            switch tab {
            case .active: active
            case .hidden: hidden
            case .reserved: reserved
            case .sold: sold
            }
        }
        set {
            let value = max(0, newValue)
            switch tab {
            case .active: active = value
            case .hidden: hidden = value
            case .reserved: reserved = value
            case .sold: sold = value
            }
        }
    }
}

/// A page of `GET /me/listings` with the counts that came with it.
struct MyListingsPage: Sendable {
    let page: Page<ListingSummary>
    let counts: MyListingCounts
}

/// `GET /me/listings` (slice B, The member's listings): everything the member sells or sold, hidden
/// listings included, newest first, 24 a page.
@MainActor
protocol MyListingsApi: AnyObject {
    /// `automatic`: a reload the member did not ask for (return to the foreground).
    func myListings(status: ListingStatus, cursor: String?, automatic: Bool) async throws(ApiError) -> MyListingsPage
}

extension GeneratedTaleedApi: MyListingsApi {
    func myListings(status: ListingStatus, cursor: String?, automatic: Bool) async throws(ApiError) -> MyListingsPage {
        let filter = TaleedAPI.ListingStatus(rawValue: status.rawValue)
        let asOf = ContinuousClock.now
        let page = try await caller.call(.read, automatic: automatic) {
            try await SellingAPI.listMyListings(status: filter, cursor: cursor, apiConfiguration: $0)
        }
        let counts = MyListingCounts(active: page.counts.active, hidden: page.counts.hidden,
                                     reserved: page.counts.reserved, sold: page.counts.sold)
        let items = page.items.map { ListingSummary($0, asOf: asOf) }
        return MyListingsPage(page: Page(items: items, nextCursor: page.nextCursor, total: page.total), counts: counts)
    }
}

/// What My listings needs. Set once at the root (`AppRootView`).
struct MyListingsDependencies {
    let listings: any MyListingsApi
    let owner: any ListingOwnerApi
}

private struct MyListingsDependenciesKey: EnvironmentKey {
    static var defaultValue: MyListingsDependencies? { nil }
}

extension EnvironmentValues {
    var myListingsDependencies: MyListingsDependencies? {
        get { self[MyListingsDependenciesKey.self] }
        set { self[MyListingsDependenciesKey.self] = newValue }
    }
}
