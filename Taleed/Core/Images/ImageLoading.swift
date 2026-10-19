import Foundation
import Nuke

/// Image loading for the whole app (api-guide.md, Images): one Nuke pipeline with a memory cache and a
/// disk cache of the downloaded files. A URL always shows the same image, so cached files never need
/// revalidating. `LazyImage`, `RemoteImage` and the design-system components all use it.
enum ImageLoading {
    /// Disk space for downloaded photos.
    static let diskCacheBytes = 300 * 1024 * 1024

    /// Call once at launch, before the first image loads.
    static func configure() {
        var configuration = ImagePipeline.Configuration.withDataCache(name: "app.taleed.images", sizeLimit: diskCacheBytes)
        // Photos are WebP and JPEG that iOS decodes; decode off the main thread, progressively.
        configuration.isProgressiveDecodingEnabled = false
        configuration.isTaskCoalescingEnabled = true
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
    }

    /// Starts downloading the images of rows about to appear (a page just received).
    static let prefetcher = ImagePrefetcher(pipeline: .shared, destination: .diskCache, maxConcurrentRequestCount: 4)

    /// Prefetches `urls` (thumbnails in lists) to the disk cache.
    static func prefetch(_ urls: [URL]) {
        prefetcher.startPrefetching(with: urls)
    }

    /// Empties both caches (debug menu).
    static func clearCaches() {
        ImagePipeline.shared.cache.removeAll()
    }
}
