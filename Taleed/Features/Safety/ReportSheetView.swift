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
    /// The content has scrolled under the title: a hairline under the header, as over the footer.
    @State private var isScrolled = false
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
            SheetHeader(title: l10n.string(.reportTitle), isClosable: !model.isSending) { dismiss() }
                .overlay(alignment: .bottom) {
                    if isScrolled { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
                }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                        Text(l10n.string(.reportSubtitle))
                            .taleedFont(TaleedFont.bodySmall)
                            .foregroundStyle(TaleedColor.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).minY < TaleedSpacing.s8 - 1 } action: {
                                isScrolled = $0
                            }
                        reasons
                        TaleedTextArea(label: l10n.string(.reportDetailsLabel), text: $model.details,
                                       placeholder: l10n.string(.reportDetailsPlaceholder),
                                       helper: "\(model.details.utf16.count) / \(ReportViewModel.maxDetailsLength)",
                                       maxLength: ReportViewModel.maxDetailsLength)
                            // Greyed out and unfocused while the report is on its way, as the other controls.
                            .disabled(model.isSending)
                            .accessibilityIdentifier("report.details")
                        evidence.id(Self.evidenceAnchor)
                    }
                    .padding(.horizontal, TaleedSize.bottomSheetPaddingX)
                    .padding(.top, TaleedSpacing.s8)
                    .padding(.bottom, TaleedSpacing.s24)
                }
                .scrollDismissesKeyboard(.interactively)
                // A screenshot that failed: its reason scrolls into view above the footer.
                .onChange(of: failureMessage) { _, message in
                    guard message != nil else { return }
                    withAnimation(.easeOut(duration: TaleedMotion.transitionMin)) {
                        proxy.scrollTo(Self.evidenceAnchor, anchor: .bottom)
                    }
                }
            }
            SheetFooterButton(title: l10n.string(.reportSubmit), isLoading: model.isSending, isEnabled: model.canSubmit,
                              error: model.error.map { l10n.message(for: $0) },
                              hint: model.reason == nil && !model.isSending ? l10n.string(.reportReasonPlaceholder) : nil) {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
            .accessibilityIdentifier("report.submit")
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
                      maxSelectionCount: max(1, model.remainingEvidence), matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            // A tile per photo at once, in its loading state: Send stays off until each is attached or failed.
            let picked = Array(zip(items, model.reserveEvidence(items.count)))
            Task {
                for (item, id) in picked where model.containsEvidence(id) {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await model.upload(id, data: data)
                    } else {
                        model.markUnreadable(id)
                    }
                }
            }
        }
        .onChange(of: failureMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }

    // MARK: Parts

    @ViewBuilder
    private var reasons: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
            FieldLabel(text: l10n.string(.reportReasonLabel))
            // Server labels, in the catalog's display order (screens.md §0.1).
            if let options = catalog.catalog?.reportReasons, !options.isEmpty {
                ForEach(options, id: \.value) { option in
                    let isSelected = model.reason == option.value
                    // Design-system §5.3: the selected choice 15/600, the others 15/400.
                    TaleedRadio(title: option.label, isSelected: isSelected,
                                textStyle: TaleedSheetStyle.option(isSelected: isSelected), indicatorEdge: .trailing) {
                        model.reason = option.value
                    }
                    .disabled(model.isSending)
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
                    EvidenceThumbnail(item: item, number: index + 1, isDisabled: model.isSending,
                                      onRetry: { Task { await model.retryEvidence(item.id) } },
                                      onRemove: { model.removeEvidence(item.id) })
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
            if let failureMessage {
                FieldHelper(text: failureMessage, color: TaleedColor.feedbackError)
                    .accessibilityIdentifier("report.evidenceError")
            }
        }
    }

    private static let evidenceAnchor = "report.evidence"

    /// The first failed screenshot's reason, then what to do: send it again, or remove it. Send waits
    /// for it, so no screenshot is left out without a word. Offline the reason is the short "Pas de
    /// connexion." (its usual "…et réessayez." would say "retry" twice).
    private var failureMessage: String? {
        guard let failed = model.evidence.first(where: \.isFailed), let error = failed.error else { return nil }
        let action = l10n.string(failed.canRetry ? .appReportEvidenceRetryOrRemove : .appReportEvidenceRemove)
        let reason = error == .network ? l10n.string(.appErrorOfflineTitle) + "." : l10n.message(for: error)
        return reason + " " + action
    }
}

/// A screenshot of the report: its preview, a spinner while the library hands it over and it uploads,
/// and once it failed either "retry" (the whole tile, when sending it again may work) or the warning,
/// with the × that removes it. VoiceOver reads "Screenshot 2, uploading" and the like.
private struct EvidenceThumbnail: View {
    let item: ReportViewModel.Evidence
    let number: Int
    let isDisabled: Bool
    let onRetry: () -> Void
    let onRemove: () -> Void
    @Environment(LanguageManager.self) private var l10n

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
            } else if item.isFailed {
                TaleedColor.errorSoft.opacity(0.85)
                if !item.canRetry {
                    TaleedIconView(.warningCircle, size: 20, color: TaleedColor.feedbackError)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous)
                .strokeBorder(item.isFailed ? TaleedColor.feedbackError : TaleedColor.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement()
        .accessibilityLabel(stateLabel)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("report.evidence.\(number)")
        .overlay {
            if item.canRetry { retryButton }
        }
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
            .disabled(isDisabled)
            .accessibilityLabel(l10n.format(.appReportRemoveScreenshot, number))
        }
    }

    /// "Capture 2, envoi en cours" / "…, jointe" / "…, échec : <reason>".
    private var stateLabel: String {
        let name = l10n.format(.appReportScreenshot, number)
        if item.isUploading { return name + ", " + l10n.string(.appReportScreenshotUploading) }
        if let error = item.error {
            return name + ", " + l10n.format(.appReportScreenshotFailed, l10n.message(for: error))
        }
        return name + ", " + l10n.string(.appReportScreenshotAttached)
    }

    /// The whole tile sends the screenshot again (64 pt, over the 44 pt minimum).
    private var retryButton: some View {
        Button(action: onRetry) {
            VStack(spacing: 2) {
                TaleedIconView(.warningCircle, size: 20, color: TaleedColor.feedbackError)
                Text(l10n.string(.commonRetry))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.feedbackError)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, TaleedSpacing.s4)
            .frame(width: 64, height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(l10n.string(.commonRetry) + ", " + l10n.format(.appReportScreenshot, number))
        .accessibilityIdentifier("report.evidence.\(number).retry")
    }
}
