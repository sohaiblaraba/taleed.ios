import SwiftUI

/// What the listing screen needs besides the shared stores. Set once at the root (`AppRootView`).
struct ListingDependencies {
    let listings: any ListingDetailApi
    let reports: any ReportsApi
    let uploads: PhotoUploadService
}

private struct ListingDependenciesKey: EnvironmentKey {
    static var defaultValue: ListingDependencies? { nil }
}

extension EnvironmentValues {
    var listingDependencies: ListingDependencies? {
        get { self[ListingDependenciesKey.self] }
        set { self[ListingDependenciesKey.self] = newValue }
    }
}

/// The listing screen (screens.md §2 G4 and §7 G4, Figma Item Detail 135:9161): back, "Item Detail",
/// share and the overflow menu (Report); then the photos, the seller's bar or the status notice, price
/// and fee, the specs, the description, the seller, the trust strip, the member's items and similar
/// items; the buy and offer buttons stay at the bottom.
///
/// States: skeleton while it loads, the error with Retry (offline included), "Cet article n'est plus
/// disponible." for a `404`, pull-to-refresh, a quiet reload after a while in the background.
struct ListingDetailView: View {
    @State private var model: ListingDetailViewModel
    @State private var presented: Presented?
    /// The offer sheet's price and bounds while it shows.
    @State private var offer: OfferDraft?
    @State private var confirmsDelete = false
    let dependencies: ListingDependencies
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(SessionManager.self) private var session
    @Environment(FavoriteStore.self) private var favorites
    @Environment(AppToasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    struct OfferDraft: Equatable {
        let price: Int
        let range: AmountRange
    }

    /// A sheet or cover over the screen.
    enum Presented: Identifiable {
        case report
        case share(URL)
        case photos(Int)

        var id: String {
            switch self {
            case .report: "report"
            case .share: "share"
            case .photos: "photos"
            }
        }
    }

    init(listingId: String, dependencies: ListingDependencies, memberId: String?) {
        self.dependencies = dependencies
        _model = State(initialValue: ListingDetailViewModel(listingId: listingId, api: dependencies.listings, memberId: memberId))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.appListingTitle), onBack: { dismiss() }, actions: barActions)
        } content: {
            content
                // Sized to its content, above the keyboard (the design-system sheet).
                .taleedSheet(isPresented: offerPresented) {
                    if let offer {
                        MakeOfferSheet(price: offer.price, range: offer.range, send: { await model.makeOffer(amount: $0) },
                                       onFinish: { outcome in
                                           self.offer = nil
                                           offerFinished(outcome)
                                       })
                    }
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { toasts.screenBottomBarHeight = $0 }
        }
        .task { await model.loadIfNeeded() }
        .onChange(of: session.user?.id) { _, id in Task { await model.memberDidChange(to: id) } }
        .onChange(of: model.refreshError) { _, error in if let error { toasts.show(error: error) } }
        .onChange(of: model.loadError) { _, error in
            // Removed, hidden or taken down: lists leave its card out too.
            if error?.isNotFound == true { favorites.markRemoved(model.listingId) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.wentToBackground()
            case .active: Task { await model.returnedToForeground() }
            default: break
            }
        }
        .sheet(item: sheetBinding) { sheet($0) }
        .fullScreenCover(item: coverBinding) { item in
            if case let .photos(index) = item, let photos = model.listing?.photos {
                ListingPhotoViewer(photos: photos, current: index)
            }
        }
        .taleedConfirmation(isPresented: confirmsDelete) {
            ConfirmationModalCard(title: l10n.string(.commonConfirmTitle), message: l10n.string(.listingDeleteConfirm),
                                  confirmTitle: l10n.string(.commonDelete),
                                  onConfirm: { confirmsDelete = false; delete() },
                                  onCancel: { confirmsDelete = false })
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let listing = model.listing, let actions = model.actions(isSignedIn: session.isSignedIn) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ListingDetailBody(listing: listing, actions: actions, model: model, handlers: handlers)
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
            .refreshable { await model.reload() }
            .accessibilityIdentifier("listing.scroll")
        } else if let error = model.loadError {
            if error.isNotFound {
                NotFoundStateView(title: l10n.string(.listingUnavailable), onBack: { dismiss() })
            } else {
                ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
            }
        } else {
            ScrollView { ListingDetailSkeleton() }.scrollDisabled(true)
        }
    }

    private var barActions: [AppBarAction] {
        guard let listing = model.listing else { return [] }
        var actions: [AppBarAction] = []
        if let url = listing.shareURL {
            actions.append(AppBarAction(icon: .shareNetwork, accessibilityLabel: l10n.string(.appA11yShare)) {
                presented = .share(url)
            })
        }
        if !listing.isOwner {
            actions.append(AppBarAction(icon: .dotsThree, accessibilityLabel: l10n.string(.commonMore), menu: [
                AppBarMenuItem(title: l10n.string(.reportAction), isDestructive: true) { start(.report) },
            ]))
        }
        return actions
    }

    private var bottomBar: some View {
        ListingDetailBottomBar(actions: model.actions(isSignedIn: session.isSignedIn), onBuy: { start(.buy) },
                               onOffer: { start(.makeOffer) },
                               onViewOrder: { model.listing?.orderId.map { router.pushSignedIn(.order(id: $0)) } })
    }

    // MARK: Sheets

    private var offerPresented: Binding<Bool> {
        Binding(get: { offer != nil }, set: { if !$0 { offer = nil } })
    }

    private var sheetBinding: Binding<Presented?> {
        Binding(get: { presented.flatMap { if case .photos = $0 { nil } else { $0 } } }, set: { presented = $0 })
    }

    private var coverBinding: Binding<Presented?> {
        Binding(get: { presented.flatMap { if case .photos = $0 { $0 } else { nil } } }, set: { presented = $0 })
    }

    @ViewBuilder
    private func sheet(_ item: Presented) -> some View {
        switch item {
        case .report:
            ReportSheetView(model: ReportViewModel(target: .listing(id: model.listingId), api: dependencies.reports,
                                                   upload: { [uploads = dependencies.uploads] data throws(ApiError) in
                                                       try await uploads.upload(data, purpose: .reportEvidence)
                                                   })) { outcome in
                switch outcome {
                case .sent: toasts.show(l10n.string(.reportSent))
                case .gone: Task { await model.reload() }
                case .failed: break
                }
            }
            .appLanguage(l10n.language)
        case let .share(url):
            ActivityShareSheet(items: [url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        case .photos:
            EmptyView()
        }
    }

    // MARK: Actions

    private var handlers: ListingDetailBody.Handlers {
        ListingDetailBody.Handlers(
            favorite: toggleFavorite,
            openPhoto: { presented = .photos($0) },
            search: { router.push(.search($0)) },
            profile: { router.push(.member(username: $0)) },
            message: { start(.message) },
            shopBundles: { start(.shopBundles) },
            toggleBundle: { start(.toggleBundle) },
            report: { start(.report) },
            edit: { router.push(.editListing(id: model.listingId)) },
            visibility: setVisibility,
            delete: { confirmsDelete = true }
        )
    }

    /// Runs a buyer's action, through sign-in when signed out (screens.md §0.5): once signed in, the
    /// listing reloads for the member and the action runs if it is still offered (not on their own item).
    private func start(_ action: ListingDetailViewModel.PendingAction) {
        if session.isSignedIn {
            perform(action)
            return
        }
        router.requireSignIn { [model, session] in
            Task {
                if let allowed = await model.resolvePending(action, memberId: session.user?.id) { perform(allowed) }
            }
        }
    }

    private func perform(_ action: ListingDetailViewModel.PendingAction) {
        guard let listing = model.listing, let actions = model.actions(isSignedIn: session.isSignedIn) else { return }
        switch action {
        case .buy:
            router.pushSignedIn(.checkout(CheckoutTarget(listingId: listing.id, offerId: actions.buy?.offerId)))
        case .makeOffer:
            if let range = listing.offerRange { offer = OfferDraft(price: listing.price, range: range) }
        case .message:
            Task { handle(await model.messageSeller()) }
        case .report:
            presented = .report
        case .shopBundles:
            if let username = listing.seller.username { router.pushSignedIn(.bundleBuilder(username: username)) }
        case .toggleBundle:
            Task { handle(await model.toggleBundle()) }
        }
    }

    private func toggleFavorite() {
        guard let listing = model.listing else { return }
        if session.isSignedIn {
            favorites.toggle(listing.summary)
        } else {
            router.requireSignIn { [favorites] in favorites.setFavorite(listing.summary, to: true) }
        }
    }

    private func setVisibility(_ visibility: ListingDetailActions.Visibility) {
        Task {
            let outcome = await model.setHidden(visibility == .hide)
            if outcome == .done {
                toasts.show(l10n.string(visibility == .hide ? .appListingHiddenToast : .appListingResumedToast))
            }
            handle(outcome)
        }
    }

    private func delete() {
        Task { handle(await model.delete()) }
    }

    private func handle(_ outcome: ListingDetailViewModel.Outcome) {
        switch outcome {
        case .done:
            break
        case let .openConversation(id):
            router.pushSignedIn(.conversation(id: id))
        case .deleted:
            favorites.markRemoved(model.listingId)
            toasts.show(l10n.string(.appListingDeletedToast))
            dismiss()
        case let .failed(error):
            toasts.show(error: error)
        }
    }

    private func offerFinished(_ outcome: ListingDetailViewModel.OfferOutcome) {
        switch outcome {
        case let .sent(conversationId):
            toasts.show(l10n.string(.offersOfferSent))
            router.pushSignedIn(.conversation(id: conversationId))
        case let .pending(conversationId):
            toasts.show(l10n.string(.offersErrorActive), kind: .info)
            router.pushSignedIn(.conversation(id: conversationId))
        case .outOfRange:
            toasts.show(l10n.string(.appErrorOfferOutOfRange), kind: .error)
        case let .failed(error):
            toasts.show(error: error)
        case .busy:
            break
        }
    }
}
