import SwiftUI

/// What the profile needs besides the shared stores. Set once at the root (`AppRootView`).
struct MemberDependencies {
    let members: any MembersApi
    let reports: any ReportsApi
    let uploads: PhotoUploadService
}

private struct MemberDependenciesKey: EnvironmentKey {
    static var defaultValue: MemberDependencies? { nil }
}

extension EnvironmentValues {
    var memberDependencies: MemberDependencies? {
        get { self[MemberDependenciesKey.self] }
        set { self[MemberDependenciesKey.self] = newValue }
    }
}

/// A member's profile (screens.md §2 G5 and §7 G5; Figma draws no profile, decision D-12: built on the
/// seller card and the product grid). Back, the handle, share and the menu (Block or Unblock, Report);
/// the header; then the "Annonces" and "Évaluations" tabs.
///
/// States: loading, the error with Retry (offline included), "no longer available" for a `404`
/// (suspended member, unknown username), each tab's own loading, error and empty states,
/// pull-to-refresh, pagination, a quiet reload after a while in the background.
struct MemberProfileView: View {
    @State private var model: MemberProfileViewModel
    @State private var presented: Presented?
    @State private var showsFilter = false
    @State private var confirmsBlock = false
    let dependencies: MemberDependencies
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(SessionManager.self) private var session
    @Environment(AppToasts.self) private var toasts
    @Environment(ListingChangeCenter.self) private var listingChanges
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    enum Presented: String, Identifiable {
        case report, share
        var id: String { rawValue }
    }

    init(username: String, wardrobe: WardrobeQuery = WardrobeQuery(), opensBundle: Bool = false,
         dependencies: MemberDependencies, memberId: String?) {
        self.dependencies = dependencies
        _model = State(initialValue: MemberProfileViewModel(username: username, wardrobe: wardrobe, opensBundle: opensBundle,
                                                            api: dependencies.members, memberId: memberId))
    }

    var body: some View {
        ShellScreen {
            // The handle from the link until the profile arrives (`displayName` is "@username").
            TaleedTopAppBar(title: (model.profile?.displayName ?? "@\(model.username)").isolatedLeftToRight,
                            onBack: { dismiss() },
                            actions: barActions)
        } content: {
            content
        }
        .task { await model.loadIfNeeded() }
        // Own profile: a listing changed in My listings or the edit form shows when back here.
        .onChange(of: listingChanges.seq) { _, _ in Task { await model.listingsChanged() } }
        .onAppear { Task { await model.appeared() } }
        .onDisappear { model.disappeared() }
        // `?bundle=1`: the bundle builder once the profile has loaded, when it offers it.
        .onChange(of: model.profile?.id) { _, _ in
            if model.takeBundleRequest() { start(.shopBundle) }
        }
        .onChange(of: session.user?.id) { _, id in Task { await model.memberDidChange(to: id) } }
        .onChange(of: model.refreshError) { _, error in if let error { toasts.show(error: error) } }
        .onChange(of: model.wardrobe.refreshError) { _, error in if let error { toasts.show(error: error) } }
        .onChange(of: model.reviews.refreshError) { _, error in if let error { toasts.show(error: error) } }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.wentToBackground()
            case .active: Task { await model.returnedToForeground() }
            default: break
            }
        }
        .taleedSheet(isPresented: $showsFilter) {
            if let profile = model.profile {
                WardrobeFilterSheet(query: model.wardrobeQuery, categories: profile.wardrobeCategories,
                                    total: profile.wardrobeTotal,
                                    onApply: { query in
                                        showsFilter = false
                                        model.applyWardrobe(query)
                                    },
                                    onClose: { showsFilter = false })
            }
        }
        .sheet(item: $presented) { sheet($0) }
        .taleedConfirmation(isPresented: confirmsBlock) {
            ConfirmationModalCard(title: l10n.format(.appProfileBlockTitle, (model.profile?.displayName ?? "").isolatedLeftToRight),
                                  message: l10n.string(.appProfileBlockBody),
                                  confirmTitle: l10n.string(.appProfileBlockConfirm),
                                  onConfirm: { confirmsBlock = false; block() },
                                  onCancel: { confirmsBlock = false },
                                  icon: .prohibit)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let profile = model.profile, let actions = model.actions {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    MemberProfileHeader(profile: profile, actions: actions, isFollowRunning: model.isRunning(.follow),
                                        isBlockRunning: model.isRunning(.block), handlers: headerHandlers)
                    Section {
                        switch model.tab {
                        case .wardrobe: MemberWardrobeSection(model: model, onFilter: { showsFilter = true })
                        case .reviews: MemberReviewsSection(list: model.reviews)
                        }
                    } header: {
                        tabs(profile)
                    }
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("member.scroll")
        } else if let error = model.loadError {
            if error.isNotFound {
                NotFoundStateView(onBack: { dismiss() })
            } else {
                ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
            }
        } else {
            // A skeleton of the header, as the listing screen loads (design-system §3.6).
            ScrollView {
                SkeletonSellerHeader().padding(TaleedLayout.screenMargin)
            }
            .scrollDisabled(true)
        }
    }

    /// "Annonces (9)" and "Évaluations (1)", as on the website; they stay at the top while scrolling.
    private func tabs(_ profile: MemberProfile) -> some View {
        let titles = [
            "\(l10n.string(.memberListings)) (\(model.wardrobeCount))",
            "\(l10n.string(.memberReviews)) (\(profile.rating?.count ?? 0))",
        ]
        return TaleedTabs(titles: titles.map(\.isolatedByContent), selection: Binding(
            get: { model.tab.rawValue },
            set: { model.tab = MemberProfileViewModel.Tab(rawValue: $0) ?? .wardrobe }
        ))
        .background(TaleedColor.surfacePrimary)
        .accessibilityIdentifier("member.tabs")
    }

    private var barActions: [AppBarAction] {
        guard let profile = model.profile, let actions = model.actions else { return [] }
        var items: [AppBarAction] = []
        if profile.shareURL != nil {
            items.append(AppBarAction(icon: .shareNetwork, accessibilityLabel: l10n.string(.appA11yShare)) {
                presented = .share
            })
        }
        var menu: [AppBarMenuItem] = []
        if actions.showsBlockMenu, actions.showsBlockedNotice {
            menu.append(AppBarMenuItem(title: l10n.string(.appProfileUnblock), icon: .user) { unblock() })
        }
        if actions.showsReport {
            menu.append(AppBarMenuItem(title: l10n.string(.appProfileReportMember), icon: .warning) { start(.report) })
        }
        // The destructive entry last, after the menu's divider (as in the conversation's menu).
        if actions.showsBlockMenu, !actions.showsBlockedNotice {
            menu.append(AppBarMenuItem(title: l10n.string(.appProfileBlock), icon: .prohibit, isDestructive: true) {
                start(.block)
            })
        }
        if !menu.isEmpty {
            items.append(AppBarAction(icon: .dotsThree, accessibilityLabel: l10n.string(.commonMore), menu: menu))
        }
        return items
    }

    @ViewBuilder
    private func sheet(_ item: Presented) -> some View {
        switch item {
        case .report:
            if let profile = model.profile {
                ReportSheetView(target: .member(id: profile.id),
                                reports: dependencies.reports, uploads: dependencies.uploads) { outcome in
                    switch outcome {
                    case .sent: toasts.show(l10n.string(.reportSent))
                    case .gone: Task { await model.reload() }
                    case .failed: break
                    }
                }
                .appLanguage(l10n.language)
            }
        case .share:
            if let url = model.profile?.shareURL {
                ActivityShareSheet(items: [url])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Actions

    private var headerHandlers: MemberProfileHeader.Handlers {
        MemberProfileHeader.Handlers(
            follow: { start(.follow) },
            unblock: unblock,
            editProfile: { router.push(.profileSettings) },
            myListings: { router.pushSignedIn(.myListings) },
            shopBundle: { start(.shopBundle) }
        )
    }

    /// Runs an action, through sign-in when signed out (screens.md §0.5): once signed in, the profile
    /// reloads for the member and the action runs if it is still offered (not on their own profile).
    private func start(_ action: MemberProfileViewModel.PendingAction) {
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

    private func perform(_ action: MemberProfileViewModel.PendingAction) {
        switch action {
        case .follow:
            Task { handle(await model.toggleFollow()) }
        case .block:
            confirmsBlock = true
        case .report:
            presented = .report
        case .shopBundle:
            router.pushSignedIn(.bundleBuilder(username: model.username))
        }
    }

    private func block() {
        Task { handle(await model.block()) }
    }

    private func unblock() {
        Task { handle(await model.unblock()) }
    }

    private func handle(_ outcome: MemberProfileViewModel.Outcome) {
        switch outcome {
        case .done:
            break
        case let .blocked(handle):
            toasts.show(l10n.format(.appProfileBlockedToast, handle.isolatedLeftToRight))
        case let .unblocked(handle):
            toasts.show(l10n.format(.appProfileUnblockedToast, handle.isolatedLeftToRight))
        case let .failed(error):
            toasts.show(error: error)
        }
    }
}
