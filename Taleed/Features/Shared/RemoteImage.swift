import NukeUI
import SwiftUI

/// A photo from the API, from the shared pipeline's caches (`ImageLoading`): a skeleton while it
/// loads, a neutral placeholder when it fails or the URL is nil. Never mirrored in Arabic.
///
/// Lists and grids pass the thumbnail (`imageUrl`, `Photo.thumbUrl`); galleries pass `Photo.url`
/// (api-guide.md, Images).
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// The placeholder's icon when there is no image.
    var placeholderIcon: TaleedIcon = .tShirt

    var body: some View {
        Rectangle()
            .fill(TaleedColor.skeleton)
            .overlay {
                if let url {
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: contentMode)
                        } else if state.error != nil {
                            placeholder
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
        TaleedIconView(placeholderIcon, size: 24, color: TaleedColor.textSecondary)
    }
}

extension URL {
    /// A URL string from the API, nil when absent or malformed.
    init?(apiString: String?) {
        guard let apiString, !apiString.isEmpty else { return nil }
        self.init(string: apiString)
    }
}
