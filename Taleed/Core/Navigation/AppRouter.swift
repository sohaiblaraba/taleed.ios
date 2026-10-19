import Observation
import SwiftUI

/// What the sign-in sheet opens on.
enum AuthEntry: Hashable, Identifiable, Sendable {
    case signIn
    /// `/r/{code}` invite links: sign-up with the code prefilled.
    case signUp(referralCode: String?)

    var id: Self { self }
}

/// The app's navigation state and its single entry point for links, pushes and in-app navigation
/// (screens.md §1). It lives outside the views, so the tab, every stack and the screens' state survive
/// a language switch, and going back restores the screen below as it was.
///
/// - In-app: `router.push(.listing(id: id))` on the current tab.
/// - Links, pushes, notification rows: `router.open(url:)` or `router.open(_ destination:)`, which pick
///   the tab and set a valid stack under the target (design-system §5.5, rule 3).
/// - Actions that need an account: `router.requireSignIn { … }` (the auth gate).
/// - Website pages: `router.openWebsite(.terms)` or `router.openInBrowser(url)`.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    private(set) var paths: [AppTab: [AppRoute]] = [:]
    /// The sign-in (or sign-up) sheet.
    var authEntry: AuthEntry?
    /// The last payment return, for the order or wallet screen to sync (then `consumePaymentReturn`).
    private(set) var pendingPaymentReturn: PaymentReturn?
    /// True while a `/listings/{id}/chat` link opens its conversation.
    private(set) var isResolvingLink = false

    // Set by `AppContainer`.
    @ObservationIgnored var isSignedIn: () -> Bool = { false }
    @ObservationIgnored var resolveConversation: ((_ listingId: String, _ buyerId: String) async throws(ApiError) -> String)?
    @ObservationIgnored var websiteLinks: () -> WebsiteLinks = { WebsiteLinks() }
    @ObservationIgnored var browser: (URL) -> Void = { InAppBrowser.open($0) }
    /// Called when a destination opens once the shell shows (a link, a push, a launch argument): the
    /// welcome screen steps aside for it.
    @ObservationIgnored var onDestinationOpened: (() -> Void)?

    /// The action waiting for sign-in, run once the sheet closes signed in.
    @ObservationIgnored private var afterSignIn: (() -> Void)?
    /// A link that arrived before the shell was on screen (launch, update check).
    @ObservationIgnored private var pendingDestination: AppDestination?
    @ObservationIgnored private var isShellReady = false

    // MARK: Stacks

    func path(_ tab: AppTab) -> [AppRoute] { paths[tab] ?? [] }

    /// The binding a tab's `NavigationStack` uses.
    func pathBinding(_ tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// Pushes a screen on the current tab: the in-app way to open a listing, a profile, an order…
    func push(_ route: AppRoute) {
        paths[selectedTab, default: []].append(route)
    }

    /// Pushes a screen that needs an account, through the sign-in gate.
    func pushSignedIn(_ route: AppRoute) {
        requireSignIn { [weak self] in self?.push(route) }
    }

    func pop() {
        guard !(paths[selectedTab]?.isEmpty ?? true) else { return }
        paths[selectedTab]?.removeLast()
    }

    func popToRoot(_ tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = []
    }

    /// The bottom navigation's selection. Selecting the current tab again returns it to its first screen.
    var tabSelection: Binding<AppTab> {
        Binding(
            get: { self.selectedTab },
            set: { tab in
                if tab == self.selectedTab { self.popToRoot(tab) }
                self.selectedTab = tab
            }
        )
    }

    // MARK: Links and pushes

    /// Opens a website address, a push's `data.url`, a notification's `url` or a `taleed://` URL.
    func open(url: URL) {
        open(LinkRouter.destination(for: url))
    }

    /// Opens a destination with a valid stack under it. Before the shell is on screen (launch), the
    /// destination waits and opens as soon as it shows.
    func open(_ destination: AppDestination) { // swiftlint:disable:this cyclomatic_complexity
        guard isShellReady else {
            pendingDestination = destination
            return
        }
        onDestinationOpened?()
        switch destination {
        case .home: show(.home, stack: [])
        case let .explore(query): show(.explore, stack: query.isEmpty ? [] : [AppRoute.search(query).reopened])
        case .sell: show(.sell, stack: [])
        case .inbox: show(.messages, stack: [])
        case .profile: show(.profile, stack: [])
        case let .screen(route):
            if route.requiresSignIn && !isSignedIn() {
                requireSignIn { [weak self] in self?.open(destination) }
            } else {
                let (tab, stack) = Self.canonicalStack(for: route)
                show(tab, stack: stack.map(\.reopened))
            }
        case let .listingChat(listingId, memberId):
            if isSignedIn() {
                resolveListingChat(listingId: listingId, memberId: memberId)
            } else {
                requireSignIn { [weak self] in self?.open(destination) }
            }
        case let .signUp(referralCode):
            if isSignedIn() { show(.home, stack: []) } else { authEntry = .signUp(referralCode: referralCode) }
        case let .paymentReturn(paymentReturn):
            pendingPaymentReturn = paymentReturn
            switch paymentReturn.kind {
            case .order: open(.screen(.order(id: paymentReturn.id)))
            case .topUp: open(.screen(.wallet))
            }
        }
    }

    /// The tab and the stack a link opens on: the target on top of the screens a member would have
    /// come through, so that back leads somewhere sensible.
    static func canonicalStack(for route: AppRoute) -> (AppTab, [AppRoute]) { // swiftlint:disable:this cyclomatic_complexity
        switch route {
        case .listing, .member: (.home, [route])
        case let .editListing(id): (.home, [.listing(id: id), route])
        case let .bundleBuilder(username): (.home, [.member(username: username), route])
        case .search, .visualSearch: (.explore, [route])
        case .conversation, .bundle: (.messages, [route])
        case let .checkout(target):
            if let bundleId = target.bundleId {
                (.messages, [.bundle(id: bundleId), route])
            } else {
                (.home, [.listing(id: target.listingId), route])
            }
        case .order: (.profile, [.orders, route])
        case .favorites, .orders, .wallet, .notifications, .settings, .referrals, .myListings: (.profile, [route])
        case .deleteAccount: (.profile, [.settings, route])
        #if DEBUG
        case .designSystem, .developerMenu: (.profile, [.settings, route])
        #endif
        }
    }

    /// The payment return the order or wallet screen should sync, once.
    func consumePaymentReturn(kind: PaymentReturn.Kind, id: String) -> PaymentReturn? {
        guard let pending = pendingPaymentReturn, pending.kind == kind, pending.id == id else { return nil }
        pendingPaymentReturn = nil
        return pending
    }

    /// Called when the shell appears: opens a link that arrived during launch.
    func shellDidAppear() {
        isShellReady = true
        if let pending = pendingDestination {
            pendingDestination = nil
            open(pending)
        }
    }

    private func show(_ tab: AppTab, stack: [AppRoute]) {
        paths[tab] = stack
        selectedTab = tab
    }

    private func resolveListingChat(listingId: String, memberId: String) {
        guard let resolveConversation else {
            open(.screen(.listing(id: listingId)))
            return
        }
        isResolvingLink = true
        Task {
            defer { isResolvingLink = false }
            do {
                let conversationId = try await resolveConversation(listingId, memberId)
                open(.screen(.conversation(id: conversationId)))
            } catch {
                // Not the seller (`403 forbidden`), a removed listing…: the listing itself.
                open(.screen(.listing(id: listingId)))
            }
        }
    }

    // MARK: Auth gate

    /// Runs `action` now when signed in; otherwise opens the sign-in sheet and runs it after sign-in.
    /// Closing the sheet without signing in drops it (screens.md §0.5: return to the action started).
    func requireSignIn(then action: @escaping () -> Void) {
        if isSignedIn() {
            action()
        } else {
            afterSignIn = action
            authEntry = .signIn
        }
    }

    /// Opens the sign-in sheet with nothing to continue.
    func presentSignIn() {
        afterSignIn = nil
        authEntry = .signIn
    }

    /// The sheet closed. Signed in: run the waiting action, once.
    func authSheetDidDismiss() {
        let action = afterSignIn
        afterSignIn = nil
        if isSignedIn() { action?() }
    }

    /// The session ended: screens that need an account leave every stack.
    func sessionDidEnd() {
        for (tab, stack) in paths {
            if let index = stack.firstIndex(where: \.requiresSignIn) {
                paths[tab] = Array(stack[..<index])
            }
        }
    }

    // MARK: Website pages

    /// Opens a website page of `GET /config` `links` in the in-app browser.
    func openWebsite(_ page: WebsitePage) {
        if let url = websiteLinks().url(for: page) { openInBrowser(url) }
    }

    /// Opens a web page in the in-app browser (`SFSafariViewController`), never an embedded web view.
    func openInBrowser(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        browser(url)
    }
}
