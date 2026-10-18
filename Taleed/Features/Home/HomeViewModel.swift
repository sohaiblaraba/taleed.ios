import Foundation
import Observation

/// The top-level categories of `GET /catalog`, in the app language.
@MainActor
@Observable
final class HomeViewModel {
    enum State: Equatable {
        case loading
        case loaded([CatalogCategory])
        case failed(ApiError)
    }

    private(set) var state: State = .loading

    @ObservationIgnored private let api: TaleedApi

    init(api: TaleedApi) {
        self.api = api
    }

    /// Loads the categories. Keeps the current list on screen while it reloads (pull-to-refresh,
    /// language switch), and shows the error state only when there is nothing to show.
    func load() async {
        if case .failed = state { state = .loading }
        do {
            state = .loaded(try await api.catalogCategories())
        } catch {
            if case .loaded = state { return }
            state = .failed(error)
        }
    }

    func retry() async {
        state = .loading
        await load()
    }
}
