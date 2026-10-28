import SwiftUI

/// One photo of a document (the ID of identity verification), built from the photo uploader's parts
/// (design-system §4.1): the label, then a 16:9 tile. Empty, the uploader's dashed `mint/50` zone with
/// `cloud-arrow-up` 28 `mint/500` and the hint in `typography.caption` `mint/600`; picked, the whole
/// photo (aspect-fit, letterboxed on `surface/grouped`, so the member sees the document's edges are in
/// frame; `border/subtle`, `radius.m`) with the uploader's remove button at the top end (44 pt target).
struct DocumentPhotoSlot: View {
    let label: String
    let hint: String
    /// The picked photo; nil shows the empty zone.
    let image: Image?
    /// VoiceOver label of the remove button.
    let removeLabel: String
    var isEnabled = true
    let onPick: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSize.inputLabelGap) {
            Text(label)
                .taleedFont(TaleedFont.caption)
                .foregroundStyle(TaleedColor.textPrimary)
                .accessibilityHidden(true)
            if let image {
                preview(image)
            } else {
                zone
            }
        }
    }

    private var zone: some View {
        Button(action: onPick) {
            // 16:9, taller when large text needs it.
            ZStack {
                Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                VStack(spacing: TaleedSpacing.s4) {
                    TaleedIconView(.cloudArrowUp, size: 28, color: TaleedColor.mintIcon)
                        .frame(width: 48, height: 48)
                    Text(hint)
                        .taleedFont(TaleedFont.caption)
                        .foregroundStyle(TaleedColor.mintText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(TaleedSpacing.s16)
            }
            .frame(maxWidth: .infinity)
            .modifier(DashedMintBox())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
    }

    private func preview(_ image: Image) -> some View {
        let shape = RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
        return Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(TaleedColor.surfaceGrouped)
            .overlay { image.resizable().scaledToFit() }
            .clipShape(shape)
            .overlay(shape.strokeBorder(TaleedColor.borderSubtle, lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    TaleedIconView(.x, size: TaleedSize.photoUploaderRemoveIcon, color: TaleedColor.textInverse)
                        .frame(width: TaleedSize.photoUploaderRemoveButton, height: TaleedSize.photoUploaderRemoveButton)
                        .background(Circle().fill(TaleedColor.toastDark))
                        // The whole 44 pt square is the button, inside the tile.
                        .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel(removeLabel)
            }
    }
}
