import SwiftUI

/// A photo in the uploader. The first one is the cover.
struct PhotoUploaderItem: Identifiable {
    let id: String
    var media: ProductMedia
}

/// Photo uploader, variant A (design-system §4.1, decision D-6): up to 5 photos, a large cover tile
/// and a 2 x 2 grid of small tiles with an add tile. Empty: a dashed upload zone.
struct PhotoUploader: View {
    let photos: [PhotoUploaderItem]
    var maxPhotos = TaleedSize.PhotoUploader.maxPhotos
    let onAdd: () -> Void
    let onRemove: (PhotoUploaderItem.ID) -> Void
    let onMakeCover: (PhotoUploaderItem.ID) -> Void
    @Environment(\.locale) private var locale

    private static let zoneSubtitleStyle = TaleedTextStyle(size: 11, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                           relativeTo: .caption2)

    var body: some View {
        VStack(alignment: .leading, spacing: photos.isEmpty ? TaleedSpacing.s4 : TaleedSpacing.s8) {
            HStack {
                Text(string(.photosLabel))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textPrimary)
                Spacer()
                Text(verbatim: DesignSystemStrings.format(.photosCount, locale: locale, photos.count, maxPhotos))
                    .taleedFont(TaleedFont.bodySmall)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
            }
            .accessibilityElement(children: .combine)
            if photos.isEmpty {
                uploadZone
            } else {
                tiles
            }
            FieldHelper(text: helper, color: TaleedColor.textSecondary)
                .accessibilityHidden(false)
        }
    }

    private var helper: String {
        switch photos.count {
        case 0, 1: string(.photosHelperEmpty)
        case maxPhotos...: DesignSystemStrings.format(.photosHelperFull, locale: locale, maxPhotos)
        default: DesignSystemStrings.format(.photosHelperSome, locale: locale, maxPhotos)
        }
    }

    private var uploadZone: some View {
        Button(action: onAdd) {
            VStack(spacing: TaleedSpacing.s4) {
                TaleedIconView(.cloudArrowUp, size: 28, color: TaleedColor.mint500)
                    .frame(width: 48, height: 48)
                Text(DesignSystemStrings.format(.photosUploadTitle, locale: locale, maxPhotos))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.mint600)
                Text(string(.photosUploadSubtitle))
                    .taleedFont(Self.zoneSubtitleStyle)
                    .foregroundStyle(TaleedColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(TaleedSpacing.s16)
            .frame(maxWidth: .infinity, minHeight: TaleedSize.PhotoUploader.emptyZoneHeight)
            .modifier(DashedMintBox())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(string(.a11yAddPhotos))
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: TaleedSize.PhotoUploader.tileGap) {
            if let cover = photos.first {
                PhotoTile(item: cover, isCover: true, onRemove: onRemove, onMakeCover: onMakeCover)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: TaleedSize.PhotoUploader.tileGap), GridItem(.flexible())],
                      spacing: TaleedSize.PhotoUploader.tileGap) {
                ForEach(photos.dropFirst()) { item in
                    PhotoTile(item: item, isCover: false, onRemove: onRemove, onMakeCover: onMakeCover)
                        .aspectRatio(1, contentMode: .fit)
                }
                if photos.count < maxPhotos {
                    addTile.aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var addTile: some View {
        Button(action: onAdd) {
            Color.clear
                .overlay { TaleedIconView(.plus, size: 20, color: TaleedColor.mint500) }
                .modifier(DashedMintBox())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(string(.a11yAddPhotos))
    }

    private func string(_ key: L10nKey) -> String { DesignSystemStrings.string(key, locale: locale) }
}

/// `mint/50` fill with a dashed `mint/400` border (4 on, 4 off).
private struct DashedMintBox: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
        content
            .background(shape.fill(TaleedColor.mint50))
            .overlay(shape.strokeBorder(TaleedColor.mint400, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}

private struct PhotoTile: View {
    let item: PhotoUploaderItem
    let isCover: Bool
    let onRemove: (PhotoUploaderItem.ID) -> Void
    let onMakeCover: (PhotoUploaderItem.ID) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
        Color.clear
            .overlay { ProductMediaView(media: item.media) }
            .clipShape(shape)
            .overlay(shape.strokeBorder(TaleedColor.borderSubtle, lineWidth: 1))
            .overlay(alignment: .topTrailing) { removeButton.padding(TaleedSize.PhotoUploader.removeInset) }
            .overlay(alignment: .bottomLeading) { coverControl.padding(TaleedSize.PhotoUploader.removeInset) }
    }

    private var removeButton: some View {
        Button { onRemove(item.id) } label: {
            TaleedIconView(.x, size: TaleedSize.PhotoUploader.removeIcon, color: TaleedColor.textInverse)
                .frame(width: TaleedSize.PhotoUploader.removeButton, height: TaleedSize.PhotoUploader.removeButton)
                .background(Circle().fill(TaleedColor.textPrimary))
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DesignSystemStrings.string(.a11yRemovePhoto, locale: locale))
    }

    @ViewBuilder
    private var coverControl: some View {
        if isCover {
            // The "Cover" badge is drawn as a Secondary Small button with a star, but it is a label.
            HStack(spacing: TaleedSpacing.s4) {
                TaleedIconView(.star, size: 20, color: nil)
                Text(DesignSystemStrings.string(.photosCover, locale: locale))
                    .taleedFont(TaleedFont.buttonSmall)
            }
            .foregroundStyle(TaleedColor.mint900)
            .padding(.vertical, 6)
            .padding(.horizontal, TaleedSpacing.s8)
            .taleedCard(fill: TaleedColor.mint400, border: TaleedColor.mint500, radius: TaleedRadius.s)
            .accessibilityElement(children: .combine)
        } else {
            TaleedIconOnlyButton(icon: .star, accessibilityLabel: DesignSystemStrings.string(.a11yMakeCover, locale: locale),
                                 kind: .tertiary, size: .small) { onMakeCover(item.id) }
        }
    }
}
