import NukeUI
import SwiftUI

/// A photo from the API, from the shared pipeline's caches (`ImageLoading`): a pulsing skeleton while
/// it loads (the skeletons' pulse, so a slow photo reads as loading, not as an empty box), a neutral
/// placeholder when it fails or the URL is nil. Never mirrored in Arabic.
///
/// Lists and grids pass the thumbnail (`imageUrl`, `Photo.thumbUrl`); galleries pass `Photo.url`
/// (api-guide.md, Images).
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// The placeholder's icon when there is no image.
    var placeholderIcon: TaleedIcon = .tShirt

    var body: some View {
        // The rectangle takes the size it is given; what it shows is drawn over it, clipped.
        Rectangle()
            .fill(Color.clear)
            .overlay {
                if let url {
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: contentMode)
                        } else if state.error != nil {
                            placeholder
                        } else {
                            TaleedColor.skeleton.skeletonPulse()
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        TaleedColor.skeleton
            .overlay { TaleedIconView(placeholderIcon, size: 24, color: TaleedColor.textSecondary) }
    }
}

extension URL {
    /// A URL string from the API, nil when absent or malformed.
    init?(apiString: String?) {
        guard let apiString, !apiString.isEmpty else { return nil }
        self.init(string: apiString)
    }
}
