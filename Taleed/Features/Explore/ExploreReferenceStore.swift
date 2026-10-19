import Foundation
import Observation

/// The brands and sizes of the filter sheet (`GET /brands`, `GET /sizes`), kept while the app runs.
/// The API caches both for 5 minutes; the sizes follow what is on sale, so they are asked again after
/// that time, the brands once per launch (and after a failure).
@MainActor
@Observable
final class ExploreReferenceStore {
    /// A list loaded on demand: nil before the first answer.
    struct Remote<Value: Sendable>: Sendable {
        var value: Value?
        var isLoading = false
        /// The last failure while no value is on screen.
        var error: ApiError?
    }

    private(set) var brands = Remote<[CatalogBrand]>()
    private(set) var sizes = Remote<[String]>()

    static let sizesLifetime: Duration = .seconds(300)

    @ObservationIgnored private let api: ExploreApi
    @ObservationIgnored private let clock: () -> ContinuousClock.Instant
    @ObservationIgnored private var sizesLoadedAt: ContinuousClock.Instant?

    init(api: ExploreApi, clock: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.api = api
        self.clock = clock
    }

    /// The brands, once (again after a failure).
    func loadBrands() async {
        guard brands.value == nil, !brands.isLoading else { return }
        brands.isLoading = true
        brands.error = nil
        defer { brands.isLoading = false }
        do {
            brands.value = try await api.brands()
        } catch {
            brands.error = error
        }
    }

    /// The brands again, now: the API refused a brand that is no longer in its list (sell form, "choose
    /// again"). A failure keeps the brands on screen.
    func refreshBrands() async {
        guard !brands.isLoading else { return }
        brands.isLoading = true
        if brands.value == nil { brands.error = nil }
        defer { brands.isLoading = false }
        do {
            brands.value = try await api.brands()
            brands.error = nil
        } catch {
            if brands.value == nil { brands.error = error }
        }
    }

    /// The sizes, when not loaded in the last 5 minutes. A failure keeps the sizes on screen.
    func loadSizes() async {
        if let loadedAt = sizesLoadedAt, clock() - loadedAt < Self.sizesLifetime { return }
        guard !sizes.isLoading else { return }
        sizes.isLoading = true
        if sizes.value == nil { sizes.error = nil }
        defer { sizes.isLoading = false }
        do {
            sizes.value = try await api.sizes()
            sizes.error = nil
            sizesLoadedAt = clock()
        } catch {
            if sizes.value == nil { sizes.error = error }
        }
    }
}
