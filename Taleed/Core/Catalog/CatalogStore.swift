import Foundation
import Observation

/// The catalog in the app language: the last good copy from disk at once (the app opens offline),
/// then `GET /catalog` at launch and after a language switch (api-guide.md, Caching).
///
/// Screens read `catalog` for labels (conditions, sorts, wilayas, reasons) and categories; nil only
/// before the first successful fetch on this device.
@MainActor
@Observable
final class CatalogStore {
    private(set) var catalog: Catalog?
    private(set) var isRefreshing = false
    /// The last refresh's failure while no catalog is on screen; nil once one is.
    private(set) var error: ApiError?

    @ObservationIgnored private let api: TaleedApi
    @ObservationIgnored private let cache: CatalogDiskCache
    @ObservationIgnored private var language: AppLanguage
    /// Drops a slow answer fetched in the previous language.
    @ObservationIgnored private var generation = 0

    init(api: TaleedApi, language: AppLanguage, cache: CatalogDiskCache = CatalogDiskCache()) {
        self.api = api
        self.cache = cache
        self.language = language
        catalog = cache.load(language: language)
    }

    /// Fetches `GET /catalog`. On failure the catalog on screen stays.
    func refresh() async {
        generation += 1
        let current = generation
        let language = self.language
        isRefreshing = true
        if catalog == nil { error = nil }
        defer { if current == generation { isRefreshing = false } }
        do {
            let fresh = try await api.catalog()
            guard current == generation else { return }
            catalog = fresh
            error = nil
            cache.save(fresh, language: language)
        } catch {
            guard current == generation else { return }
            self.error = catalog == nil ? error : nil
        }
    }

    /// The member switched language: show that language's copy from disk, then fetch it again.
    func languageDidChange(to language: AppLanguage) async {
        guard language != self.language else { return }
        self.language = language
        generation += 1
        catalog = cache.load(language: language) ?? catalog
        await refresh()
    }
}

/// The last good catalog of each language, as JSON in Application Support (not a cache directory
/// that iOS may purge while offline).
struct CatalogDiskCache: Sendable {
    private static let schemaVersion = 1
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Catalog", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func load(language: AppLanguage) -> Catalog? {
        guard let data = try? Data(contentsOf: fileURL(language)),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == Self.schemaVersion else { return nil }
        return stored.catalog
    }

    func save(_ catalog: Catalog, language: AppLanguage) {
        guard let data = try? JSONEncoder().encode(Stored(version: Self.schemaVersion, catalog: catalog)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(language), options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL(_ language: AppLanguage) -> URL {
        directory.appending(path: "catalog-\(language.rawValue).json")
    }

    private struct Stored: Codable {
        let version: Int
        let catalog: Catalog
    }
}
