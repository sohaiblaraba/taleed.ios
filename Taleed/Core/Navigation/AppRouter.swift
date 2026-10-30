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
    /// The selected tab and every tab's stack, in one value: a link changes both in a single mutation, so
    /// no view can draw the new tab over the old stack, or read one of them before the other is set.
    private struct Navigation {
        var selectedTab: AppTab = .home
        var paths: [AppTab: [AppRoute]] = [:]
    }

    private var navigation = Navigation()

    var selectedTab: AppTab {
        get { navigation.selectedTab }
        set { navigation.selectedTab = newValue }
    }

    var paths: [AppTab: [AppRoute]] { navigation.paths }
    /// The sign-in (or sign-up) sheet.
    var authEntry: AuthEntry?
    /// True while a `/listings/{id}/chat` link opens its conversation.
    private(set) var isResolvingLink = false

    // Set by `AppContainer`.
    @ObservationIgnored var isSignedIn: () -> Bool = { false }
    /// The account is suspended: the suspended screen shows instead of the shell, so links and pushes
    /// wait (`suspensionDidLift`) rather than open over it (a website page in the in-app browser).
    @ObservationIgnored var isSuspended: () -> Bool = { false }
    /// `POST /conversations`: the conversation about a listing; `buyerId` only for the seller (`?with=`).
    @ObservationIgnored var resolveConversation: ((_ listingId: String, _ buyerId: String?) async throws(ApiError) -> String)?
    @ObservationIgnored var websiteLinks: () -> WebsiteLinks = { WebsiteLinks() }
    @ObservationIgnored var browser: (URL) -> Void = { InAppBrowser.open($0) }
    /// Called when a destination opens after the launch (a link, a push, a launch argument): the
    /// welcome screen steps aside for it.
    @ObservationIgnored var onDestinationOpened: (() -> Void)?
    /// Called when a link or a push opens the notifications screen: one already open reloads and marks
    /// read again (`NotificationsFeed`).
    @ObservationIgnored var onNotificationsOpened: (() -> Void)?

    /// The action waiting for sign-in, run once the sheet closes signed in.
    @ObservationIgnored private var afterSignIn: (() -> Void)?
    /// A link that arrived before the launch flow finished (`GET /config`, the session restored), or
    /// while the account is suspended. Only the latest one is kept.
    @ObservationIgnored private var pendingDestination: AppDestination?
    @ObservationIgnored private var isLaunchFinished = false

    // MARK: Stacks

    func path(_ tab: AppTab) -> [AppRoute] { paths[tab] ?? [] }

    /// The binding a tab's `NavigationStack` uses.
    func pathBinding(_ tab: AppTab) -> Binding<[AppRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.navigation.paths[tab] = $0 })
    }

    /// Pushes a screen on the current tab: the in-app way to open a listing, a profile, an order…
    func push(_ route: AppRoute) {
        navigation.paths[selectedTab, default: []].append(route)
    }

    /// Pushes a screen that needs an account, through the sign-in gate.
    func pushSignedIn(_ route: AppRoute) {
        requireSignIn { [weak self] in self?.push(route) }
    }

    /// Replaces a screen of a stack by another one in place (checkout by its order's payment screen), so
    /// that back skips it. The route is looked for on the current tab first; when it is no longer in any
    /// stack, the new screen is pushed on the current tab.
    func replace(_ route: AppRoute, with newRoute: AppRoute) {
        let tabs = [selectedTab] + AppTab.allCases.filter { $0 != selectedTab }
        for tab in tabs {
            if var stack = paths[tab], let index = stack.lastIndex(of: route) {
                stack[index] = newRoute
                navigation.paths[tab] = Array(stack[...index])
                return
            }
        }
        push(newRoute)
    }

    /// Opens a screen that may already sit right under the current one (an order under its dispute
    /// thread): goes back to it rather than stacking a copy (screens.md §1, no duplicate screens on a
    /// stack). Pushes it when the current screen was reached another way, such as a link.
    func pushOrGoBack(to route: AppRoute) {
        let stack = paths[selectedTab] ?? []
        if stack.count >= 2, stack[stack.count - 2] == route {
            pop()
        } else {
            push(route)
        }
    }

    func pop() {
        guard !(paths[selectedTab]?.isEmpty ?? true) else { return }
        navigation.paths[selectedTab]?.removeLast()
    }

    func popToRoot(_ tab: AppTab? = nil) {
        navigation.paths[tab ?? selectedTab] = []
    }

    /// The bottom navigation's selection. Selecting the current tab again returns it to its first screen.
    var tabSelection: Binding<AppTab> {
        Binding(
            get: { self.selectedTab },
            set: { tab in
                if tab == self.selectedTab {
                    self.popToRoot(tab)
                } else {
                    self.selectedTab = tab
                }
            }
        )
    }

    /// The conversation on top of the selected tab: a push for it shows nothing in the foreground (slice C).
    var conversationOnScreen: String? {
        if case let .conversation(id, _) = path(selectedTab).last { return id }
        return nil
    }

    // MARK: Links and pushes

    /// Opens a website address, a push's `data.url`, a notification's `url` or a `taleed://` URL.
    func open(url: URL) {
        open(LinkRouter.destination(for: url))
    }

    /// Opens a destination with a valid stack under it. During launch the destination waits for the launch
    /// flow (`launchWillShowItsScreen`), which knows whether the member is signed in; while the account is
    /// suspended it waits for the suspension to lift (`suspensionDidLift`), and is dropped if the
    /// session ends instead.
    func open(_ destination: AppDestination) { // swiftlint:disable:this cyclomatic_complexity
        guard isLaunchFinished, !isSuspended() else {
            pendingDestination = destination
            return
        }
        // The welcome screen steps aside after the tab and its stack are set, never between them.
        defer { onDestinationOpened?() }
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
                if route == .notifications { onNotificationsOpened?() }
            }
        case let .listingChat(listingId, memberId):
            if isSignedIn() {
                resolveListingChat(listingId: listingId, memberId: memberId) { [weak self] in self?.open(.screen($0)) }
            } else {
                requireSignIn { [weak self] in self?.open(destination) }
            }
        case let .signUp(referralCode):
            if isSignedIn() { show(.home, stack: []) } else { authEntry = .signUp(referralCode: referralCode) }
        case let .paymentReturn(paymentReturn):
            // The payment screen syncs the order whatever `result` says.
            let attempt: PaymentAttempt = paymentReturn.succeeded ? .returnedSuccess : .returnedFailure
            open(.screen(.orderPayment(OrderPaymentTarget(orderId: paymentReturn.id, attempt: attempt))))
        case let .web(url):
            openInBrowser(url)
        }
    }

    /// Opens a link that a screen shows (a notification row): a screen goes on top of the current tab,
    /// so that back returns to the screen the member tapped it on; a screen already on top stays as it is.
    /// A tab (Home, the inbox…), a payment return or sign-up opens as a link does.
    func openFromScreen(_ destination: AppDestination) {
        switch destination {
        case let .screen(route):
            guard path(selectedTab).last != route else { return }
            if route.requiresSignIn {
                pushSignedIn(route.reopened)
            } else {
                push(route.reopened)
            }
        case let .explore(query) where !query.isEmpty:
            push(AppRoute.search(query).reopened)
        case let .listingChat(listingId, memberId):
            // On the tab it was tapped on, even when the member switched tabs while it resolved; once.
            guard !isResolvingLink else { return }
            let tab = selectedTab
            requireSignIn { [weak self] in
                self?.resolveListingChat(listingId: listingId, memberId: memberId) { route in
                    self?.navigation.paths[tab, default: []].append(route)
                }
            }
        case .home, .explore, .sell, .inbox, .profile, .signUp, .paymentReturn, .web:
            open(destination)
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
        case .order, .orderPayment, .dispute: (.profile, [.orders, route])
        case .favorites, .orders, .wallet, .payoutDetails, .notifications, .settings, .referrals, .myListings: (.profile, [route])
        case .deleteAccount, .profileSettings, .usernameSettings, .emailSettings, .passwordSettings, .addresses, .blockedMembers,
             .identityVerification, .help:
            (.profile, [.settings, route])
        #if DEBUG
        case .designSystem: (.profile, [.settings, route])
        #endif
        #if DEBUG || TALEED_TEST_TOOLS
        case .developerMenu: (.profile, [.settings, route])
        #endif
        }
    }

    /// Called by the launch flow once it knows the session, just before its screen (the shell) shows:
    /// opens a link that arrived during launch now, so that the shell's first frame already has its tab
    /// and stack. Opening it from the shell's `onAppear` raced with that first frame: SwiftUI could draw
    /// the shell in the middle of the change, the content of the old tab under the new tab's button.
    func launchWillShowItsScreen() {
        guard !isLaunchFinished else { return }
        isLaunchFinished = true
        if let pending = pendingDestination {
            pendingDestination = nil
            open(pending)
        }
    }

    /// The suspension was lifted (`GET /me` answered again on return to the foreground): the shell shows
    /// again, with a link that came meanwhile.
    func suspensionDidLift() {
        guard isLaunchFinished, !isSuspended(), let pending = pendingDestination else { return }
        pendingDestination = nil
        open(pending)
    }

    private func show(_ tab: AppTab, stack: [AppRoute]) {
        var navigation = navigation
        navigation.paths[tab] = stack
        navigation.selectedTab = tab
        self.navigation = navigation
    }

    /// `POST /conversations`, then `present` the conversation, or the listing when that fails.
    private func resolveListingChat(listingId: String, memberId: String?, present: @escaping (AppRoute) -> Void) {
        guard let resolveConversation else {
            present(.listing(id: listingId))
            return
        }
        isResolvingLink = true
        Task {
            defer { isResolvingLink = false }
            do {
                let conversationId = try await resolveConversation(listingId, memberId)
                // The member writes first, like "Envoyer un message" (or the seller after a "new favorite"
                // notification): the keyboard opens.
                present(.conversation(id: conversationId, focusesComposer: true))
            } catch {
                // Not the seller (`403 forbidden`), one's own listing, a removed listing…: the listing itself.
                present(.listing(id: listingId))
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

    /// Closes the sign-in sheet, and forgets what it was to continue (the account was deleted).
    func closeSignIn() {
        afterSignIn = nil
        authEntry = nil
    }

    /// The sheet closed. Signed in: run the waiting action, once.
    func authSheetDidDismiss() {
        let action = afterSignIn
        afterSignIn = nil
        if isSignedIn() { action?() }
    }

    /// The session ended: screens that need an account leave every stack, and a link held while the
    /// account was suspended is dropped (the member signed out of the suspended screen).
    func sessionDidEnd() {
        if isLaunchFinished { pendingDestination = nil }
        var navigation = navigation
        for (tab, stack) in navigation.paths {
            if let index = stack.firstIndex(where: \.requiresSignIn) {
                navigation.paths[tab] = Array(stack[..<index])
            }
        }
        self.navigation = navigation
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

    /// The trust shield of the app bars (Search results, Checkout): opens the buyer-protection page of
    /// `GET /config` `links` in the in-app browser (Saad, 2026-10-22). Without the link (config not
    /// loaded) the shield stays a plain indicator.
    func buyerProtectionAction(accessibilityLabel: String) -> AppBarAction {
        let hasLink = websiteLinks().url(for: .buyerProtection) != nil
        return AppBarAction(icon: .shieldCheck, accessibilityLabel: accessibilityLabel,
                            action: hasLink ? { [weak self] in self?.openWebsite(.buyerProtection) } : nil,
                            accessibilityIdentifier: "appBar.buyerProtection")
    }
}
