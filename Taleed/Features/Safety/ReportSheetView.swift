import PhotosUI
import SwiftUI

/// The report sheet (screens.md §2 G19, website `report-dialog.tsx`): title and the confidentiality
/// note, the reasons of `GET /catalog` as radio rows, optional details, up to 3 screenshots, and
/// "Envoyer le signalement". Never offered on the member's own listing, profile or conversation.
///
/// `onFinish` gets `.sent` (the thank-you) or `.gone` (the target was removed); the sheet closes itself.
struct ReportSheetView: View {
    @State private var model: ReportViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsPicker = false
    let onFinish: (ReportViewModel.Outcome) -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    init(model: ReportViewModel, onFinish: @escaping (ReportViewModel.Outcome) -> Void) {
        _model = State(initialValue: model)
        self.onFinish = onFinish
    }

    /// The sheet for `target`, its screenshots uploaded as `report_evidence`.
    init(target: ReportTarget, reports: any ReportsApi, uploads: PhotoUploadService,
         onFinish: @escaping (ReportViewModel.Outcome) -> Void) {
        self.init(model: ReportViewModel(target: target, api: reports, upload: { data throws(ApiError) in
            #if DEBUG
            try ReportDebugFailures.fail(.upload)
            #endif
            return try await uploads.upload(data, purpose: .reportEvidence)
        }), onFinish: onFinish)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                    Text(l10n.string(.reportSubtitle))
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                    reasons
                    TaleedTextArea(label: l10n.string(.reportDetailsLabel), text: $model.details,
                                   placeholder: l10n.string(.reportDetailsPlaceholder),
                                   helper: "\(model.details.utf16.count) / \(ReportViewModel.maxDetailsLength)")
                    evidence
                }
                .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
                .padding(.top, TaleedSpacing.s8)
                .padding(.bottom, TaleedSpacing.s24)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
        .presentationDragIndicator(.hidden)
        .presentationBackground(TaleedColor.surfacePrimary)
        .interactiveDismissDisabled(model.isSending)
        .task {
            if catalog.catalog?.reportReasons.isEmpty ?? true { await catalog.refresh() }
        }
        .photosPicker(isPresented: $showsPicker, selection: $pickerItems,
                      maxSelectionCount: max(1, ReportViewModel.maxEvidence - model.evidence.count), matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task {
                for item in items.prefix(ReportViewModel.maxEvidence - model.evidence.count) {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await model.addEvidence(data)
                    } else {
                        model.addUnreadableEvidence()
                    }
                }
            }
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: TaleedSize.bottomSheetGap) {
            Capsule()
                .fill(TaleedColor.sheetHandle)
                .frame(width: TaleedSize.bottomSheetHandleWidth, height: TaleedSize.bottomSheetHandleHeight)
                .accessibilityHidden(true)
            HStack {
                Text(l10n.string(.reportTitle))
                    .taleedFont(TaleedTextStyle(size: 18, weight: .regular, lineHeight: nil, letterSpacing: 0, relativeTo: .body))
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { dismiss() } label: {
                    TaleedIconView(.x, size: 20, color: TaleedColor.textSecondary)
                        .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.string(.commonClose))
                .disabled(model.isSending)
            }
        }
        .padding(.top, TaleedSize.bottomSheetPaddingTop)
        .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
        .padding(.bottom, TaleedSpacing.s8)
    }

    @ViewBuilder
    private var reasons: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
            FieldLabel(text: l10n.string(.reportReasonLabel))
            // Server labels, in the catalog's display order (screens.md §0.1).
            if let options = catalog.catalog?.reportReasons, !options.isEmpty {
                ForEach(options, id: \.value) { option in
                    TaleedRadio(title: option.label, isSelected: model.reason == option.value) {
                        model.reason = option.value
                    }
                    .accessibilityIdentifier("report.reason.\(option.value)")
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

    private var evidence: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            FieldLabel(text: l10n.string(.reportEvidenceLabel))
            HStack(spacing: TaleedSpacing.s8) {
                ForEach(Array(model.evidence.enumerated()), id: \.element.id) { index, item in
                    EvidenceThumbnail(item: item, removeLabel: l10n.format(.photoUploaderRemove, index + 1)) {
                        model.removeEvidence(item.id)
                    }
                }
                if model.canAddEvidence {
                    Button { showsPicker = true } label: {
                        TaleedIconView(.plus, size: 20, color: TaleedColor.textSecondary)
                            .frame(width: 64, height: 64)
                            .overlay(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous)
                                .strokeBorder(TaleedColor.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(l10n.string(.appReportAddPhoto))
                    .accessibilityIdentifier("report.addPhoto")
                }
            }
            if let failed = model.evidence.first(where: { $0.error != nil })?.error {
                FieldHelper(text: l10n.message(for: failed), color: TaleedColor.feedbackError)
            }
        }
    }

    /// The send failure sits above the button, where it is seen without scrolling.
    private var footer: some View {
        VStack(spacing: TaleedSpacing.s12) {
            if let error = model.error {
                InlineAlert(kind: .error, title: l10n.message(for: error))
                    .accessibilityIdentifier("report.error")
            }
            sendButton
        }
        .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
        .padding(.top, TaleedSpacing.s12)
        .padding(.bottom, TaleedSpacing.s16)
        .background(TaleedColor.surfacePrimary)
        .overlay(alignment: .top) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
        .onChange(of: model.error) { _, error in
            if let error { AccessibilityNotification.Announcement(l10n.message(for: error)).post() }
        }
    }

    private var sendButton: some View {
        TaleedButton(title: l10n.string(.reportSubmit), kind: .primary, size: .large, isLoading: model.isSending,
                     isFullWidth: true) {
            Task {
                guard let outcome = await model.submit() else { return }
                switch outcome {
                case .sent, .gone:
                    onFinish(outcome)
                    dismiss()
                case .failed:
                    break
                }
            }
        }
        .disabled(!model.canSubmit)
        .accessibilityIdentifier("report.submit")
    }
}

/// A screenshot of the report: its preview, a spinner while it uploads, a warning when it failed,
/// and the × that removes it.
private struct EvidenceThumbnail: View {
    let item: ReportViewModel.Evidence
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
