import Foundation
@testable import Taleed
import Testing

/// The catalog opens from disk, refreshes at launch and after a language switch (api-guide.md, Caching).
@MainActor
struct CatalogStoreTests {
    private let api = FakeTaleedApi()
    private let cache = CatalogDiskCache(directory: FileManager.default.temporaryDirectory
        .appending(path: "catalog-tests-\(UUID().uuidString)", directoryHint: .isDirectory))

    @Test func refreshStoresTheCatalogOnDisk() async {
        let store = CatalogStore(api: api, language: .fr, cache: cache)
        #expect(store.catalog == nil)
        await store.refresh()
        #expect(store.catalog == .fixture())
        #expect(cache.load(language: .fr) == .fixture())
        #expect(cache.load(language: .ar) == nil)
    }

    @Test func theDiskCopyShowsAtOnceAndStaysWhenOffline() async {
        cache.save(.fixture(), language: .fr)
        api.catalogResult = .failure(.network)
        let store = CatalogStore(api: api, language: .fr, cache: cache)
        #expect(store.catalog == .fixture())
        await store.refresh()
        #expect(store.catalog == .fixture())
        #expect(store.error == nil)
    }

    @Test func noCopyAndNoNetworkIsAnError() async {
        api.catalogResult = .failure(.network)
        let store = CatalogStore(api: api, language: .fr, cache: cache)
        await store.refresh()
        #expect(store.catalog == nil)
        #expect(store.error == .network)
    }

    @Test func languageSwitchFetchesAgain() async {
        let arabic = Catalog.fixture(categories: [CatalogCategory(id: "c1", slug: "femmes", name: "نساء")])
        cache.save(arabic, language: .ar)
        let store = CatalogStore(api: api, language: .fr, cache: cache)
        await store.refresh()
        api.catalogResult = .failure(.network)
        await store.languageDidChange(to: .ar)
        // Offline: the Arabic copy from disk.
        #expect(store.catalog == arabic)
        #expect(api.catalogCalls == 2)
    }

    @Test func lookups() {
        let catalog = Catalog.fixture(categories: [
            CatalogCategory(id: "c1", slug: "femmes", name: "Femmes",
                            children: [CatalogCategory(id: "c2", slug: "robes", name: "Robes")]),
        ])
        #expect(catalog.category(slug: "robes")?.name == "Robes")
        #expect(catalog.category(slug: "femmes")?.id == "c1")
        #expect(catalog.category(slug: "x") == nil)
        #expect(catalog.condition("VERY_GOOD")?.shortLabel == "Très bon")
        #expect(catalog.condition("BRAND_NEW") == nil)
        #expect(catalog.wilaya(16)?.name == "Alger")
    }
}
