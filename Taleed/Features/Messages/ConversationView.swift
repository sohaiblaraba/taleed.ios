import PhotosUI
import SwiftUI
import UIKit

/// The conversation screen (screens.md §2 G9 and §7 G9; no Figma screen, decision D-12): the other
/// member in the app bar (opens their profile) with the menu (Signaler, Bloquer or Débloquer, Voir
/// l’annonce, Voir le profil); the item under it (opens the listing); the messages from the bottom up,
/// older pages as the member scrolls up; the composer, or why the conversation takes no reply.
///
/// Live: the events stream while the screen is on top and the app in the foreground; read marks when
/// it opens and when the other member writes. States: loading, the error with Retry (offline included),
/// "no longer available" for a `404`, the "sending" and "Non envoyé" bubbles.
struct ConversationView: View {
    let route: AppRoute
    let focusesComposer: Bool
    let dependencies: MessagesDependencies
    @State private var model: ConversationViewModel
    @State private var presented: Presented?
    @State private var confirmsBlock = false
    @State private var choosesPhotoSource = false
    @State private var showsLibrary = false
    @State private var showsCamera = false
    @State private var pickedItem: PhotosPickerItem?
    /// The offer sheet showing (G10).
    @State private var offerSheet: ConversationOfferSheet?
    /// The offer waiting for "Accepter" to be confirmed (G10).
    @State private var accepting: ChatOffer?
    @FocusState private var composerFocused: Bool
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(SessionManager.self) private var session
    @Environment(AppToasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.shellTab) private var shellTab
    @Environment(\.pushRegistration) private var push

    enum Presented: Identifiable {
        case report
        case photo(URL)

        var id: String {
            switch self {
            case .report: "report"
            case let .photo(url): url.absoluteString
            }
        }
    }

    init(conversationId: String, route: AppRoute, focusesComposer: Bool, dependencies: MessagesDependencies) {
        self.route = route
        self.focusesComposer = focusesComposer
        self.dependencies = dependencies
        let uploads = dependencies.uploads
        _model = State(initialValue: ConversationViewModel(
            conversationId: conversationId, api: dependencies.messages, events: dependencies.events,
            members: dependencies.members, offers: dependencies.offers,
            upload: { data throws(ApiError) in try await uploads.upload(data, purpose: .chatPhoto) }
        ))
    }

    var body: some View {
        ShellScreen {
            ConversationAppBar(member: model.conversation?.counterpart, isLoaded: model.conversation != nil, onBack: { dismiss() },
                               onProfile: profileAction, menu: menuItems)
        } content: {
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
                // Toasts show above the composer while this screen is on top.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if let shellTab { toasts.setBottomBarHeight(height, tab: shellTab, route: route) }
                }
        }
        .task {
            model.onRead = { [session, reads = dependencies.reads, id = model.conversationId] counts in
                session.updateUnreadCounts(messages: counts.messages, notifications: counts.notifications)
                // The inbox's row loses its bold and counter with the badge.
                reads.didRead(conversationId: id)
            }
            // The moment that explains the push permission (screens.md §2 G9 Ops), when pushes are on.
            model.onSent = { [push] in Task { await push?.memberReachedOut() } }
            await model.loadIfNeeded()
        }
        // The stream runs while the screen shows: closed in the background, under another screen or tab.
        .task(id: LiveKey(isLoaded: model.conversation != nil && model.loadError == nil, isVisible: isVisible)) {
            await model.setVisible(isVisible)
            guard isVisible, model.conversation != nil else { return }
            await model.followLiveUpdates()
        }
        // The pinned offer's buttons go away when it lapses, with no message from the server (G10).
        .task(id: model.pinnedOffer.map(OfferExpiryKey.init)) { await model.followOfferExpiry() }
        .onChange(of: model.conversation != nil) { _, loaded in
            // "Message the seller": the keyboard opens with the conversation.
            if loaded, focusesComposer, model.conversation?.canReply == true { composerFocused = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.returnedToForeground() } }
        }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            show(notice)
        }
        .sheet(item: sheetBinding) { _ in reportSheet }
        .fullScreenCover(item: coverBinding) { item in
            if case let .photo(url) = item {
                ListingPhotoViewer(photos: [ListingPhoto(id: url.absoluteString, url: url, thumbURL: nil)], current: 0)
            }
        }
        .taleedSheet(isPresented: $choosesPhotoSource) { photoSourceSheet }
        .photosPicker(isPresented: $showsLibrary, selection: $pickedItem, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.attachPhoto(data)
                } else {
                    toasts.show(l10n.string(.sellErrorUpload), kind: .error)
                }
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { image in
                showsCamera = false
                guard let data = image?.jpegData(compressionQuality: 0.95) else { return }
                Task { await model.attachPhoto(data) }
            }
            .ignoresSafeArea()
        }
        .taleedConfirmation(isPresented: confirmsBlock) {
            ConfirmationModalCard(
                title: l10n.format(.appProfileBlockTitle, (model.conversation?.counterpart?.displayName ?? "").isolatedLeftToRight),
                message: l10n.string(.appProfileBlockBody),
                confirmTitle: l10n.string(.appProfileBlockConfirm),
                onConfirm: {
                    confirmsBlock = false
                    Task { await model.setBlocked(true) }
                },
                onCancel: { confirmsBlock = false },
                // Blocking is not deleting: the prohibit sign, the trash stays for deletions.
                icon: .prohibit
            )
        }
    }

    /// On top of the selected tab, with the app in the foreground.
    private var isVisible: Bool {
        guard scenePhase == .active, let shellTab else { return false }
        return router.selectedTab == shellTab && router.path(shellTab).last == route
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let error = model.loadError {
            if error.isNotFound {
                NotFoundStateView(onBack: { dismiss() })
            } else {
                ErrorStateView(error: error, retry: { Task { await model.load() } }, onBack: { dismiss() })
            }
        } else if let conversation = model.conversation {
            VStack(spacing: 0) {
                if let listing = conversation.listing {
                    ConversationListingStrip(listing: listing) { router.push(.listing(id: listing.id)) }
                        .fixedSize(horizontal: false, vertical: true)
                }
                ConversationPinnedOffer(model: model, counterpartName: conversation.counterpart?.displayName,
                                        isComposing: composerFocused, sheet: $offerSheet, accepting: $accepting,
                                        endComposing: { composerFocused = false })
                ConversationMessageList(model: model, isOfficial: conversation.isOfficial,
                                        openPhoto: { presented = .photo($0) }, openLink: openLink)
            }
            .modifier(ConversationOfferPresenter(model: model, counterpartName: conversation.counterpart?.displayName,
                                                 sheet: $offerSheet, accepting: $accepting))
        } else {
            LoadingStateView()
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if let conversation = model.conversation, model.loadError == nil {
            VStack(spacing: 0) {
                // The tab bar that carries the offline banner is hidden here (as on Android).
                OfflineBanner()
                if let notice = ChatText.readOnlyNotice(for: conversation) {
                    ConversationReadOnlyBar(notice: notice, isUnblocking: model.isChangingBlock) {
                        Task { await model.setBlocked(false) }
                    }
                } else {
                    composer
                }
            }
        }
    }

    private var composer: some View {
        @Bindable var model = model
        return ChatComposer(text: $model.text, photo: model.photo, canSend: model.canSend, focus: $composerFocused,
                            offerTitle: model.offerEntry.map { l10n.string($0.titleKey) }, onOffer: { offerSheet = .make(for: model) },
                            onSend: { Task { await model.send() } }, onAddPhoto: addPhoto, onRemovePhoto: model.removePhoto)
    }

    // MARK: Menu

    private var profileAction: (() -> Void)? {
        guard let username = model.conversation?.counterpart?.username else { return nil }
        return { router.push(.member(username: username)) }
    }

    private var menuItems: [AppBarMenuItem] {
        let actions = model.menuActions
        var items: [AppBarMenuItem] = []
        if actions.viewListing, let listing = model.conversation?.listing {
            items.append(AppBarMenuItem(title: l10n.string(.chatViewListing), icon: .storefront) { router.push(.listing(id: listing.id)) })
        }
        if actions.viewProfile, let profileAction {
            items.append(AppBarMenuItem(title: l10n.string(.listingViewProfile), icon: .user, action: profileAction))
        }
        if actions.unblock {
            items.append(AppBarMenuItem(title: l10n.string(.appProfileUnblock), icon: .user) { Task { await model.setBlocked(false) } })
        }
        if actions.report {
            items.append(AppBarMenuItem(title: l10n.string(.reportAction), icon: .warning) { presented = .report })
        }
        // The destructive entry last, after the menu's divider.
        if actions.block {
            items.append(AppBarMenuItem(title: l10n.string(.appProfileBlock), icon: .prohibit, isDestructive: true) {
                confirmsBlock = true
            })
        }
        return items
    }

    // MARK: Sheets

    private var sheetBinding: Binding<Presented?> {
        Binding(get: { if case .report = presented { presented } else { nil } }, set: { presented = $0 })
    }

    private var coverBinding: Binding<Presented?> {
        Binding(get: { if case .photo = presented { presented } else { nil } }, set: { presented = $0 })
    }

    private var reportSheet: some View {
        ReportSheetView(target: .conversation(id: model.conversationId),
                        reports: dependencies.reports, uploads: dependencies.uploads) { outcome in
            switch outcome {
            case .sent: toasts.show(l10n.string(.reportSent))
            case .gone: Task { await model.reloadConversation(automatic: false) }
            case .failed: break
            }
        }
        .appLanguage(l10n.language)
    }

    /// With a camera: "Prendre une photo" or the library. Without one (the simulator): the library at once.
    private func addPhoto() {
        composerFocused = false
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            choosesPhotoSource = true
        } else {
            showsLibrary = true
        }
    }

    private var photoSourceSheet: some View {
        TaleedBottomSheet(title: l10n.string(.chatAddPhoto), onClose: { choosesPhotoSource = false }, content: {
            VStack(spacing: TaleedSpacing.s12) {
                TaleedButton(title: l10n.string(.appVisualTakePhoto), kind: .secondary, size: .large, isFullWidth: true) {
                    choosesPhotoSource = false
                    showsCamera = true
                }
                TaleedButton(title: l10n.string(.appSellPhotoLibrary), kind: .outline, size: .large, isFullWidth: true) {
                    choosesPhotoSource = false
                    showsLibrary = true
                }
            }
        })
    }

    // MARK: Links and toasts

    /// A link of an announcement or its button: Taleed's own pages through the router (like a push), other
    /// sites in the in-app browser.
    /// Taleed's own addresses open in the app, any other web address in the in-app browser (`LinkRouter`).
    private func openLink(_ url: URL) {
        router.open(url: url)
    }

    private func show(_ notice: ConversationViewModel.Notice) {
        switch notice {
        case let .error(error): toasts.show(error: error)
        case let .blocked(handle): toasts.show(l10n.format(.appProfileBlockedToast, handle.isolatedLeftToRight))
        case let .unblocked(handle): toasts.show(l10n.format(.appProfileUnblockedToast, handle.isolatedLeftToRight))
        case let .confirmation(key): toasts.show(l10n.string(key))
        case let .information(key): toasts.show(l10n.string(key), kind: .info)
        }
    }
}

private struct LiveKey: Hashable {
    let isLoaded: Bool
    let isVisible: Bool
}

/// The pinned offer and its deadline: a new one restarts the wait for its expiry.
private struct OfferExpiryKey: Hashable {
    let offerId: String
    let isPending: Bool
    let expiresAt: Date

    init(_ pinned: PinnedOffer) {
        offerId = pinned.offer.id
        isPending = pinned.offer.status == .pending
        expiresAt = pinned.offer.expiresAt
    }
}
