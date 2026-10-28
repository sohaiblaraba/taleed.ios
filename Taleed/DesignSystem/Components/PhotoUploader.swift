import SwiftUI

/// A photo in the uploader. The first one is the cover.
struct PhotoUploaderItem: Identifiable {
    /// Where the photo's upload stands (slice B, Selling: each photo is uploaded as soon as it is picked).
    enum Status {
        case ready
        /// A spinner over the photo.
        case uploading
        /// Failed: "Réessayer" on the photo when sending it again may work (no answer, a server failure),
        /// otherwise the reason on the photo (too large, a format the API refuses): only removing helps.
        case failed(message: String, canRetry: Bool)
    }

    let id: String
    var media: ProductMedia
    var status: Status = .ready
}

/// Photo uploader, variant A (design-system §4.1, decision D-6): up to 5 photos, a large cover tile
/// and a 2 x 2 grid of small tiles with an add tile. Empty: a dashed upload zone.
struct PhotoUploader: View {
    let photos: [PhotoUploaderItem]
    var maxPhotos = TaleedSize.photoUploaderMaxPhotos
    let onAdd: () -> Void
    let onRemove: (PhotoUploaderItem.ID) -> Void
    let onMakeCover: (PhotoUploaderItem.ID) -> Void
    /// Sends a failed photo again.
    var onRetry: ((PhotoUploaderItem.ID) -> Void)?
    /// The Error look of the fields (design-system §2.4): the label and the empty upload zone's border in
    /// `feedback/error` (a failed photo has its own red border). The error text is the caller's.
    var hasError = false
    @Environment(\.locale) private var locale

    private static let zoneSubtitleStyle = TaleedTextStyle(size: 11, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                           relativeTo: .caption2)

    var body: some View {
        VStack(alignment: .leading, spacing: photos.isEmpty ? TaleedSpacing.s4 : TaleedSpacing.s8) {
            HStack {
                Text(string(.photoUploaderLabel))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(hasError ? TaleedColor.feedbackError : TaleedColor.textPrimary)
                Spacer()
                Text(verbatim: DesignSystemStrings.format(.photoUploaderCount, locale: locale, photos.count, maxPhotos))
                    .taleedFont(TaleedFont.bodySmall)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
            }
            .accessibilityElement(children: .combine)
            if photos.isEmpty {
                uploadZone
            } else {
                tiles
            }
            FieldHelper(text: helper, color: TaleedColor.textSecondarySmall)
                .accessibilityHidden(false)
        }
    }

    private var helper: String {
        switch photos.count {
        case 0, 1: string(.photoUploaderHelperEmpty)
        case maxPhotos...: DesignSystemStrings.format(.photoUploaderHelperFull, locale: locale, maxPhotos)
        default: DesignSystemStrings.format(.photoUploaderHelperSome, locale: locale, maxPhotos)
        }
    }

    private var uploadZone: some View {
        Button(action: onAdd) {
            VStack(spacing: TaleedSpacing.s4) {
                TaleedIconView(.cloudArrowUp, size: 28, color: TaleedColor.mintIcon)
                    .frame(width: 48, height: 48)
                Text(DesignSystemStrings.format(.photoUploaderZoneTitle, locale: locale, maxPhotos))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.mintText)
                Text(string(.photoUploaderZoneBody))
                    .taleedFont(Self.zoneSubtitleStyle)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
            }
            .multilineTextAlignment(.center)
            .padding(TaleedSpacing.s16)
            .frame(maxWidth: .infinity, minHeight: TaleedSize.photoUploaderEmptyZoneHeight)
            .modifier(DashedMintBox(hasError: hasError))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(string(.photoUploaderLabel))
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: TaleedSize.photoUploaderTileGap) {
            if let cover = photos.first {
                PhotoTile(item: cover, number: 1, onRemove: onRemove, onMakeCover: onMakeCover, onRetry: onRetry)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: TaleedSize.photoUploaderTileGap), GridItem(.flexible())],
                      spacing: TaleedSize.photoUploaderTileGap) {
                ForEach(Array(photos.enumerated().dropFirst()), id: \.element.id) { index, item in
                    PhotoTile(item: item, number: index + 1, onRemove: onRemove, onMakeCover: onMakeCover, onRetry: onRetry)
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
                .overlay { TaleedIconView(.plus, size: 20, color: TaleedColor.mintIcon) }
                .modifier(DashedMintBox())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(string(.photoUploaderLabel))
    }

    private func string(_ key: L10nKey) -> String { DesignSystemStrings.string(key, locale: locale) }
}

/// `mint/50` fill with a dashed `mint/400` border (4 on, 4 off): the uploader's empty zone and add tile.
/// On error the border is `feedback/error`, as a field's.
struct DashedMintBox: ViewModifier {
    var hasError = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
        content
            .background(shape.fill(TaleedColor.mintTint))
            .overlay(shape.strokeBorder(hasError ? TaleedColor.feedbackError : TaleedColor.brandAccent,
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .animation(.easeInOut(duration: TaleedMotion.transitionMin), value: hasError)
    }
}

private struct PhotoTile: View {
    let item: PhotoUploaderItem
    /// 1-based position; the first photo is the cover. VoiceOver reads "Photo 2", "Remove photo 2".
    let number: Int
    let onRemove: (PhotoUploaderItem.ID) -> Void
    let onMakeCover: (PhotoUploaderItem.ID) -> Void
    let onRetry: ((PhotoUploaderItem.ID) -> Void)?
    @Environment(\.locale) private var locale

    private var isCover: Bool { number == 1 }

    /// Failed in a way sending it again cannot fix: the tile keeps only the reason and the remove button.
    private var needsRemoving: Bool {
        if case .failed(_, canRetry: false) = item.status { return true }
        return false
    }

    private var hasFailed: Bool {
        if case .failed = item.status { return true }
        return false
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
        Color.clear
            .overlay { ProductMediaView(media: item.media) }
            .overlay { statusLayer }
            .clipShape(shape)
            .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isImage)
            .overlay { failureLayer }
            .overlay(alignment: .topTrailing) { removeButton.padding(TaleedSize.photoUploaderRemoveInset) }
            .overlay(alignment: .bottomLeading) {
                // A failed cover shows only its failure until the retry works.
                if !needsRemoving, !(isCover && hasFailed) { coverControl.padding(TaleedSize.photoUploaderRemoveInset) }
            }
    }

    private var borderColor: Color {
        if case .failed = item.status { return TaleedColor.feedbackError }
        return TaleedColor.borderSubtle
    }

    /// "Photo 2, Cover", then the upload's state.
    private var accessibilityText: String {
        var parts = [DesignSystemStrings.format(.photoUploaderPhoto, locale: locale, number)]
        if isCover { parts.append(DesignSystemStrings.string(.photoUploaderCover, locale: locale)) }
        switch item.status {
        case .ready: break
        case .uploading: parts.append(DesignSystemStrings.string(.commonLoading, locale: locale))
        case let .failed(message, _): parts.append(message)
        }
        return parts.joined(separator: ", ")
    }

    /// A dimmed photo under a spinner while it uploads; a light error wash once it failed.
    @ViewBuilder
    private var statusLayer: some View {
        switch item.status {
        case .ready:
            EmptyView()
        case .uploading:
            ZStack {
                TaleedColor.photoBusyOverlay
                ProgressView().tint(TaleedColor.textInverse)
            }
            .accessibilityHidden(true)
        case .failed:
            TaleedColor.errorSoft.opacity(0.85)
                .accessibilityHidden(true)
        }
    }

    /// A failed photo: the warning and "Réessayer", centred, the whole wash a 44 pt target or more; or,
    /// when sending it again cannot work, the warning and the reason (the tile reads it to VoiceOver).
    @ViewBuilder
    private var failureLayer: some View {
        if case let .failed(message, canRetry) = item.status {
            if canRetry, let onRetry {
                retryButton(onRetry)
            } else {
                // A small tile: the reason alone when the warning does not fit above it.
                ViewThatFits(in: .vertical) {
                    VStack(spacing: TaleedSpacing.s4) {
                        TaleedIconView(.warningCircle, size: 20, color: TaleedColor.feedbackError)
                        reason(message, lines: 3)
                    }
                    reason(message, lines: 4)
                }
                // Below the remove button.
                .padding(.horizontal, TaleedSpacing.s4)
                .padding(.top, TaleedSize.photoUploaderRemoveInset + TaleedSize.photoUploaderRemoveButton)
                .padding(.bottom, TaleedSpacing.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func reason(_ message: String, lines: Int) -> some View {
        Text(message)
            .taleedFont(TaleedFont.caption)
            .foregroundStyle(TaleedColor.feedbackError)
            .multilineTextAlignment(.center)
            .lineLimit(lines)
            .minimumScaleFactor(0.6)
    }

    private func retryButton(_ onRetry: @escaping (PhotoUploaderItem.ID) -> Void) -> some View {
        Button { onRetry(item.id) } label: {
            VStack(spacing: TaleedSpacing.s4) {
                TaleedIconView(.warningCircle, size: 20, color: TaleedColor.feedbackError)
                Text(DesignSystemStrings.string(.commonRetry, locale: locale))
                    .taleedFont(TaleedFont.buttonSmall)
                    .foregroundStyle(TaleedColor.feedbackError)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(TaleedSpacing.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DesignSystemStrings.string(.commonRetry, locale: locale) + ", "
            + DesignSystemStrings.format(.photoUploaderPhoto, locale: locale, number))
    }

    private var removeButton: some View {
        Button { onRemove(item.id) } label: {
            TaleedIconView(.x, size: TaleedSize.photoUploaderRemoveIcon, color: TaleedColor.textInverse)
                .frame(width: TaleedSize.photoUploaderRemoveButton, height: TaleedSize.photoUploaderRemoveButton)
                .background(Circle().fill(TaleedColor.toastDark))
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DesignSystemStrings.format(.photoUploaderRemove, locale: locale, number))
    }

    @ViewBuilder
    private var coverControl: some View {
        if isCover {
            // The "Cover" badge is drawn as a Secondary Small button with a star, but it is a label.
            HStack(spacing: TaleedSpacing.s4) {
                TaleedIconView(.star, size: 20, color: nil)
                Text(DesignSystemStrings.string(.photoUploaderCover, locale: locale))
                    .taleedFont(TaleedFont.buttonSmall)
            }
            .foregroundStyle(TaleedColor.onBrandAccent)
            .padding(.vertical, 6)
            .padding(.horizontal, TaleedSpacing.s8)
            .taleedCard(fill: TaleedColor.brandAccent, border: TaleedColor.brandAccentPressed, radius: TaleedRadius.s)
            // The tile already says "cover".
            .accessibilityHidden(true)
        } else {
            TaleedIconOnlyButton(icon: .star,
                                 accessibilityLabel: DesignSystemStrings.format(.photoUploaderMakeCover, locale: locale, number),
                                 kind: .tertiary, size: .small) { onMakeCover(item.id) }
        }
    }
}
