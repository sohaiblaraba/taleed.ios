import PhotosUI
import SwiftUI
import UIKit

/// The photo-search sheet (design-system bottom sheet): the website's title, the hint "a photo of the
/// item alone…" (slice B), "Take a photo" (when the device has a camera) and "Import a photo"; while
/// the search runs, the photo with a scanning frame and the website's rotating steps; on failure, the
/// message with Retry when the same photo may work.
struct VisualSearchSheet: View {
    let model: VisualSearchModel
    /// The search found its results, or Taleed turned photo search off: the caller closes the sheet.
    let onOutcome: (VisualSearchModel.Outcome) -> Void
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsLibrary = false
    @State private var showsCamera = false
    @State private var stage = 0
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    private static let stages: [L10nKey] = [.visualStageAnalyze, .visualStageStyle, .visualStageMatch]
    private static let stageInterval: Duration = .milliseconds(1400)

    var body: some View {
        TaleedBottomSheet(title: l10n.string(.visualTitle), onClose: model.isSearching ? nil : { dismiss() }) {
            VStack(spacing: TaleedSpacing.s16) {
                switch model.phase {
                case .pick:
                    hint
                    actions
                case .searching:
                    preview
                    progress
                case let .failed(error, canRetry):
                    preview
                    InlineAlert(kind: .error, title: message(for: error))
                    if canRetry {
                        TaleedButton(title: l10n.string(.commonRetry), kind: .primary, size: .large, isFullWidth: true) {
                            Task { await finish(model.retry()) }
                        }
                    }
                    actions
                }
            }
        }
        .interactiveDismissDisabled(model.isSearching)
        .photosPicker(isPresented: $showsLibrary, selection: $pickerItem, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                let data: Data?
                do {
                    data = try await item.loadTransferable(type: Data.self)
                } catch {
                    // An iCloud photo that cannot download (offline…).
                    model.photoUnreadable(downloadFailed: true)
                    return
                }
                guard let data else {
                    model.photoUnreadable(downloadFailed: false)
                    return
                }
                await finish(model.search(data))
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { image in
                showsCamera = false
                guard let image else { return }  // Cancelled.
                guard let data = image.jpegData(compressionQuality: 0.95) else {
                    model.photoUnreadable(downloadFailed: false)
                    return
                }
                Task { await finish(model.search(data)) }
            }
            .ignoresSafeArea()
        }
        .task(id: model.isSearching) {
            stage = 0
            while model.isSearching, !Task.isCancelled {
                try? await Task.sleep(for: Self.stageInterval)
                stage = (stage + 1) % Self.stages.count
            }
        }
    }

    private var hint: some View {
        Text(l10n.string(.appVisualHint))
            .taleedFont(TaleedFont.bodyRegular)
            .foregroundStyle(TaleedColor.textBody)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: TaleedSpacing.s12) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                TaleedButton(title: l10n.string(.appVisualTakePhoto), kind: .secondary, size: .large, isFullWidth: true) {
                    showsCamera = true
                }
            }
            TaleedButton(title: l10n.string(.visualImport), kind: UIImagePickerController.isSourceTypeAvailable(.camera)
                ? .outline : .secondary, size: .large, isFullWidth: true) {
                showsLibrary = true
            }
            .accessibilityIdentifier("visual.import")
        }
    }

    /// The photo, square, with the scanning frame of the website's dialog.
    @ViewBuilder
    private var preview: some View {
        if let data = model.photo, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous)
                        .strokeBorder(TaleedColor.brandPrimary.opacity(0.6), lineWidth: 2)
                        .padding(TaleedSpacing.s8)
                }
                .accessibilityLabel(l10n.string(.visualYourPhoto))
        }
    }

    private var progress: some View {
        HStack(spacing: TaleedSpacing.s8) {
            ProgressView().tint(TaleedColor.brandPrimary)
            Text(l10n.string(Self.stages[stage]))
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textBody)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: TaleedMotion.transitionMax), value: stage)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// "Could not analyze" for a server failure (the website's message), the error's own text otherwise
    /// (offline, a photo too large, a format the API refuses).
    private func message(for error: ApiError) -> String {
        switch error {
        case .server: l10n.string(.visualErrorGeneric)
        default: l10n.message(for: error)
        }
    }

    private func finish(_ outcome: VisualSearchModel.Outcome) async {
        if outcome != .failed { onOutcome(outcome) }
    }
}

/// The system camera, for a photo to search with (shown only when the device has a camera).
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

/// Photo-search results (screens.md §2 G3, website `visual-search/[id]`): the analyzed photo with
/// "Articles similaires" and the count, the website's notice when the matches are weak, then the items
/// in the two-column grid, page by page. No match: the website's sentence; an expired search (`404`
/// after 24 hours): "start a new search".
struct VisualSearchResultsView: View {
    @State private var viewModel: VisualSearchResultsViewModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(FavoriteStore.self) private var favorites
    @Environment(ListingChangeCenter.self) private var listingChanges
    @Environment(AppToasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    init(id: String, api: any ExploreApi) {
        _viewModel = State(initialValue: VisualSearchResultsViewModel(id: id, api: api))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.visualTitle), onBack: { dismiss() })
        } content: {
            content
        }
        .task { await viewModel.results.loadIfNeeded() }
        .onChange(of: viewModel.results.refreshError) { _, error in
            if let error { toasts.show(error: error) }
        }
    }

    @ViewBuilder
    private var content: some View {
        let list = viewModel.results
        if list.hasLoaded {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                    header
                        .padding(.horizontal, TaleedLayout.screenMargin)
                    let listings = listingChanges.cards(list.items.filter { !favorites.removedIds.contains($0.id) })
                    if listings.isEmpty {
                        EmptyState(title: l10n.string(.visualNoResults), actionTitle: l10n.string(.appVisualNewSearch),
                                   action: newSearch)
                            .padding(.top, TaleedSpacing.s16)
                    } else {
                        if viewModel.weakMatch {
                            InlineAlert(kind: .warning, title: l10n.string(.visualWeakMatches))
                                .padding(.horizontal, TaleedLayout.screenMargin)
                        }
                        ListingGrid(listings: listings)
                        PaginationFooter(list: list)
                    }
                }
                .padding(.vertical, TaleedSpacing.s16)
            }
            .refreshable { await list.refresh() }
        } else if viewModel.hasExpired {
            CenteredStateColumn {
                EmptyState(title: l10n.string(.appVisualExpiredTitle), message: l10n.string(.appVisualExpiredBody),
                           actionTitle: l10n.string(.appVisualNewSearch), action: newSearch, icon: .clock)
            }
        } else if let error = list.error {
            ErrorStateView(error: error, retry: { Task { await list.reload() } }, onBack: { dismiss() })
        } else {
            ScrollView {
                SkeletonProductGrid(count: TaleedMotion.skeletonMaxPlaceholders)
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.top, TaleedSpacing.s16)
            }
            .scrollDisabled(true)
        }
    }

    /// The analyzed photo (80, as on the website), the title and the count.
    private var header: some View {
        HStack(spacing: TaleedSpacing.s16) {
            ProductMediaView(media: .remote(viewModel.photoURL))
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Text(l10n.string(.visualResultsTitle))
                    .taleedFont(TaleedFont.title2)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(l10n.format(.visualResultsCount, viewModel.results.total ?? 0))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A new search starts from Explore (where the camera button is).
    private func newSearch() {
        router.open(.explore(ExploreQuery()))
    }
}
