import SwiftUI

/// What the Explore screens need besides the shared stores: the search and photo-search calls, and
/// the photo preparation of uploads. Set once at the root (`AppRootView`).
struct ExploreDependencies {
    let listings: any ListingsApi
    let explore: any ExploreApi
}

private struct ExploreDependenciesKey: EnvironmentKey {
    static var defaultValue: ExploreDependencies? { nil }
}

extension EnvironmentValues {
    var exploreDependencies: ExploreDependencies? {
        get { self[ExploreDependenciesKey.self] }
        set { self[ExploreDependenciesKey.self] = newValue }
    }
}
