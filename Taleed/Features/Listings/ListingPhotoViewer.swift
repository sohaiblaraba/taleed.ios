import NukeUI
import SwiftUI
import UIKit

/// The listing's photos full screen (the website's gallery lightbox): swipe between them, pinch or
/// double-tap to zoom, the "1 / 4" count, and close. Photos never mirror.
struct ListingPhotoViewer: View {
    let photos: [ListingPhoto]
    @State var current: Int
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(photos.indices, id: \.self) { index in
                    ZoomablePhoto(url: photos[index].url).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            HStack {
                Button { dismiss() } label: {
                    TaleedIconView(.x, size: 20, color: TaleedColor.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(TaleedColor.surfacePrimary))
                        .contentShape(Circle())
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.string(.commonClose))
                .accessibilityIdentifier("photoViewer.close")
                Spacer()
                if photos.count > 1 {
                    PageCountPill(current: current + 1, total: photos.count)
                }
            }
            .padding(.horizontal, TaleedSpacing.s16)
            .padding(.top, TaleedSpacing.s8)
        }
        .environment(\.layoutDirection, l10n.language.layoutDirection)
    }
}

/// One photo, fitted, that zooms up to 4× with a pinch and toggles 2× with a double tap.
private struct ZoomablePhoto: View {
    let url: URL?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFit()
            } else {
                ProgressView().tint(TaleedColor.textInverse)
            }
        }
        .scaleEffect(scale)
        .offset(offset)
        .gesture(magnification.simultaneously(with: scale > 1 ? drag : nil))
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: TaleedMotion.transitionMin)) {
                scale = scale > 1 ? 1 : 2
                lastScale = scale
                offset = .zero
                lastOffset = .zero
            }
        }
        .accessibilityAddTraits(.isImage)
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = min(4, max(1, lastScale * value.magnification)) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }
}

/// The system share sheet for the listing's `shareUrl`.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
