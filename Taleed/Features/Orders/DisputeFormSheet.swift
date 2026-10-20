import PhotosUI
import SwiftUI

/// The dispute form (screens.md §2 G12 screen 4 and §7 G12; website `order-actions.tsx` dialog): the
/// title "Signaler un problème" and the website's notice, the reasons of `GET /catalog` as radio rows,
/// "Décrivez le problème" (10 to 2 000 characters), the evidence photos with their hint (required or
/// optional for the reason), and "Ouvrir le litige".
///
/// `onFinish` gets `.opened` (the thread opens) or `.orderChanged` (the order is reloaded); the sheet
/// closes itself.
struct DisputeFormSheet: View {
    @State private var model: DisputeFormViewModel
    let onFinish: (DisputeFormViewModel.Outcome) -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    init(model: DisputeFormViewModel, onFinish: @escaping (DisputeFormViewModel.Outcome) -> Void) {
        _model = State(initialValue: model)
        self.onFinish = onFinish
    }

    private var reasons: [DisputeReasonOption] { catalog.catalog?.disputeReasons ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: l10n.string(.disputesOpenTitle), isClosable: !model.isSending) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                    Text(l10n.string(.ordersDisputeBanner))
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                    reasonList
                    TaleedTextArea(label: l10n.string(.disputesDescribe), text: $model.description,
                                   placeholder: l10n.string(.disputesDescribePlaceholder),
                                   helper: descriptionHelper,
                                   error: model.descriptionRejected ? minimumText : nil)
                        .accessibilityIdentifier("dispute.description")
                    EvidencePhotosField(photos: model.photos, isRequired: model.needsEvidence(in: reasons),
                                        hint: l10n.string(model.needsEvidence(in: reasons)
                                            ? .disputesEvidenceRequiredHint : .disputesEvidenceOptionalHint),
                                        isDisabled: model.isSending)
                    if let error = model.error {
                        InlineAlert(kind: .error, title: l10n.message(for: error))
                    }
                }
                .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
                .padding(.top, TaleedSpacing.s8)
                .padding(.bottom, TaleedSpacing.s24)
            }
            .scrollDismissesKeyboard(.interactively)
            SheetFooterButton(title: l10n.string(.disputesSubmit), isLoading: model.isSending,
                              isEnabled: model.canSubmit(reasons: reasons)) {
                Task {
                    guard let outcome = await model.submit(reasons: reasons) else { return }
                    switch outcome {
                    case .opened, .orderChanged:
                        onFinish(outcome)
                        dismiss()
                    case .failed:
                        break
                    }
                }
            }
            .accessibilityIdentifier("dispute.submit")
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
        .presentationDragIndicator(.hidden)
        .presentationBackground(TaleedColor.surfacePrimary)
        .interactiveDismissDisabled(model.isSending || model.photos.isUploading)
        .task {
            if reasons.isEmpty { await catalog.refresh() }
            model.setReasons(reasons)
        }
        .onChange(of: reasons) { _, reasons in model.setReasons(reasons) }
    }

    /// "Au moins 10 caractères."
    private var minimumText: String {
        l10n.format(.appDisputeDescriptionMin, DisputeFormViewModel.minDescription)
    }

    /// "12 / 2000"; under 10 characters, the minimum with it.
    private var descriptionHelper: String {
        let count = "\(model.trimmedDescription.utf16.count) / \(DisputeFormViewModel.maxDescription)"
        guard !model.isDescriptionLongEnough else { return count }
        let minimum = minimumText.hasSuffix(".") ? String(minimumText.dropLast()) : minimumText
        return "\(minimum) · \(count)"
    }

    @ViewBuilder
    private var reasonList: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
            FieldLabel(text: l10n.string(.disputesReason))
            // Server labels, in the catalog's order (screens.md §0.1).
            if !reasons.isEmpty {
                ForEach(reasons, id: \.value) { option in
                    TaleedRadio(title: option.label, isSelected: model.reason == option.value, indicatorEdge: .trailing) {
                        model.reason = option.value
                    }
                    .disabled(model.isSending)
                    .accessibilityIdentifier("dispute.reason.\(option.value)")
                }
            } else if catalog.isRefreshing || catalog.error == nil {
                ProgressView()
                    .tint(TaleedColor.brandPrimary)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .accessibilityLabel(l10n.string(.commonLoading))
            } else if let error = catalog.error {
                InlineAlert(kind: .error, title: l10n.message(for: error), actionTitle: l10n.string(.commonRetry)) {
                    Task { await catalog.refresh() }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The review form (screens.md §2 G12 screen 6; website review dialog): "Évaluer la transaction", the
/// stars (5 by default), an optional comment (1 000 characters at most) and "Envoyer l'évaluation".
struct ReviewFormSheet: View {
    @State private var model: ReviewFormViewModel
    let onFinish: (ReviewFormViewModel.Outcome) -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    init(model: ReviewFormViewModel, onFinish: @escaping (ReviewFormViewModel.Outcome) -> Void) {
        _model = State(initialValue: model)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: l10n.string(.reviewsRateTransaction), isClosable: !model.isSending) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                    VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                        FieldLabel(text: l10n.string(.reviewsRating))
                        RatingPicker(rating: $model.rating)
                    }
                    TaleedTextArea(label: l10n.string(.reviewsComment), text: $model.comment,
                                   placeholder: l10n.string(.reviewsCommentPlaceholder),
                                   helper: "\(model.comment.utf16.count) / \(ReviewFormViewModel.maxComment)")
                        .accessibilityIdentifier("review.comment")
                    if let error = model.error {
                        InlineAlert(kind: .error, title: l10n.message(for: error))
                    }
                }
                .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
                .padding(.top, TaleedSpacing.s8)
                .padding(.bottom, TaleedSpacing.s24)
            }
            .scrollDismissesKeyboard(.interactively)
            SheetFooterButton(title: l10n.string(.reviewsSubmit), isLoading: model.isSending, isEnabled: model.canSubmit) {
                Task {
                    guard let outcome = await model.submit() else { return }
                    switch outcome {
                    case .reviewed, .orderChanged:
                        onFinish(outcome)
                        dismiss()
                    case .failed:
                        break
                    }
                }
            }
            .accessibilityIdentifier("review.submit")
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
        .presentationDragIndicator(.hidden)
        .presentationBackground(TaleedColor.surfacePrimary)
        .interactiveDismissDisabled(model.isSending)
    }
}

/// Five stars to tap, left to right in every language (the website's `RatingStars` in its large
/// size), each a 44 pt target that VoiceOver reads as "4 étoiles", and adjustable as one control.
struct RatingPicker: View {
    @Binding var rating: Int
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(spacing: TaleedSpacing.s4) {
            ForEach(ReviewFormViewModel.minRating...ReviewFormViewModel.maxRating, id: \.self) { star in
                Button {
                    rating = star
                } label: {
                    StarShape()
                        .fill(star <= rating ? TaleedColor.warningIcon : Color.clear)
                        .overlay(StarShape().stroke(star <= rating ? TaleedColor.warningIcon
                            : TaleedColor.textSecondary.opacity(0.45), lineWidth: 1.5))
                        .frame(width: 32, height: 32)
                        .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.star.\(star)")
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.string(.reviewsRating))
        .accessibilityValue(l10n.format(.reviewsStars, rating))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(ReviewFormViewModel.maxRating, rating + 1)
            case .decrement: rating = max(ReviewFormViewModel.minRating, rating - 1)
            @unknown default: break
            }
        }
    }
}

/// "Preuves photos" (with * when required), the photos with their remove button, "+" while fewer than
/// 4, the hint, and the first upload error.
struct EvidencePhotosField: View {
    let photos: EvidencePhotos
    let isRequired: Bool
    let hint: String
    var isDisabled = false
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            FieldLabel(text: l10n.string(.disputesEvidencePhotos) + (isRequired ? " *" : ""))
            EvidencePhotosRow(photos: photos, isDisabled: isDisabled)
            FieldHelper(text: hint, color: TaleedColor.textSecondary)
            if let failed = photos.firstError {
                FieldHelper(text: l10n.message(for: failed), color: TaleedColor.feedbackError)
            }
        }
    }
}

/// The photos and the "+" that picks more (the system photo picker, up to what is left of 4).
struct EvidencePhotosRow: View {
    let photos: EvidencePhotos
    var isDisabled = false
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TaleedSpacing.s8) {
                ForEach(photos.items) { item in
                    EvidenceThumbnailView(item: item, removeLabel: l10n.string(.disputesRemovePhoto)) {
                        photos.remove(item.id)
                    }
                }
                if photos.remaining > 0 {
                    EvidencePickerButton(photos: photos, isDisabled: isDisabled) {
                        TaleedIconView(.plus, size: 20, color: TaleedColor.textSecondary)
                            .frame(width: 64, height: 64)
                            .overlay(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous)
                                .strokeBorder(TaleedColor.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .accessibilityLabel(l10n.string(.disputesAddPhotos))
                    .accessibilityIdentifier("dispute.addPhoto")
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// The system photo picker for evidence photos, up to what is left of 4; each picked photo uploads.
struct EvidencePickerButton<Label: View>: View {
    let photos: EvidencePhotos
    var isDisabled = false
    @ViewBuilder let label: Label
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, photos.remaining), matching: .images) {
            label.contentShape(Rectangle())
        }
        .disabled(isDisabled || photos.remaining == 0)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task {
                for item in items.prefix(photos.remaining) {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    await photos.add(data)
                }
            }
        }
    }
}

/// A picked photo: its preview, a spinner while it uploads, a warning when it failed, and the ×.
private struct EvidenceThumbnailView: View {
    let item: EvidencePhotos.Item
    let removeLabel: String
    let onRemove: () -> Void

    var body: some View {
        ZStack {
            if let preview = item.preview {
                Image(uiImage: preview).resizable().scaledToFill()
            } else {
                TaleedColor.surfaceSubtle
            }
            if item.isUploading {
                TaleedColor.textPrimary.opacity(0.35)
                ProgressView().tint(TaleedColor.textInverse)
            } else if item.error != nil {
                TaleedColor.errorSoft.opacity(0.85)
                TaleedIconView(.warningCircle, size: 20, color: TaleedColor.feedbackError)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                TaleedIconView(.x, size: 12, color: TaleedColor.textPrimary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(TaleedColor.surfacePrimary.opacity(0.9)))
                    .contentShape(Rectangle())
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
            .padding(2)
            .accessibilityLabel(removeLabel)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The header of a full-height form sheet (dispute, review, report, shipping label): the design-system
/// sheet heading, padded as `TaleedBottomSheet` over a scrolling body.
struct SheetHeader: View {
    let title: String
    var isClosable = true
    let onClose: () -> Void

    var body: some View {
        TaleedSheetHeading(title: title, onClose: onClose, isCloseDisabled: !isClosable)
            .padding(.top, TaleedSize.bottomSheetPaddingTop)
            .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
            .padding(.bottom, TaleedSpacing.s8)
    }
}

/// The full-width primary button at the bottom of a form sheet, over a divider. `error` (a failed send)
/// sits above the button, where it is seen without scrolling, and VoiceOver announces it.
struct SheetFooterButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    var error: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: TaleedSpacing.s12) {
            if let error {
                InlineAlert(kind: .error, title: error)
                    .accessibilityIdentifier("sheet.error")
            }
            TaleedButton(title: title, kind: .primary, size: .large, isLoading: isLoading, isFullWidth: true, action: action)
                .disabled(!isEnabled)
        }
        .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
        .padding(.top, TaleedSpacing.s12)
        .padding(.bottom, TaleedSpacing.s16)
        .background(TaleedColor.surfacePrimary)
        .overlay(alignment: .top) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
        .announcesFieldError(error)
    }
}
