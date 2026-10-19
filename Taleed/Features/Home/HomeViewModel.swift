import Foundation
import Observation

/// The top-level categories of the catalog, in the app language, from `CatalogStore` (shown from the
/// disk copy at once, then refreshed).
@MainActor
@Observable
final class HomeViewModel {
    enum State: Equatable {
        case loading
        case loaded([CatalogCategory])
        case failed(ApiError)
    }

    @ObservationIgnored private let catalog: CatalogStore

    init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    /// The categories on screen while the catalog reloads (pull-to-refresh, language switch); the error
    /// state only when there is nothing to show.
    var state: State {
        if let loaded = catalog.catalog { return .loaded(loaded.categories) }
        if let error = catalog.error, !catalog.isRefreshing { return .failed(error) }
        return .loading
    }

    /// Loads the catalog unless the launch already is.
    func load() async {
        guard !catalog.isRefreshing else { return }
        await catalog.refresh()
    }

    /// Pull-to-refresh and the error state's "Retry".
    func retry() async {
        await catalog.refresh()
    }
}
