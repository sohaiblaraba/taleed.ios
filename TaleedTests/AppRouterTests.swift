import Foundation
@testable import Taleed
import Testing

@MainActor
struct AppRouterTests {
    private let signedIn = SignedIn()
    private let router = AppRouter()

    init() {
        router.isSignedIn = { [signedIn] in signedIn.value }
        router.launchWillShowItsScreen()
    }

    @Test func listingOpensOnHomeWithTheListingOnTop() {
        router.selectedTab = .profile
        router.open(url: URL(string: "https://taleed.app/listings/l1")!)
        #expect(router.selectedTab == .home)
        #expect(router.path(.home) == [.listing(id: "l1")])
    }

    @Test func orderOpensOverTheOrdersList() {
        signedIn.value = true
        router.open(.screen(.order(id: "o1")))
        #expect(router.selectedTab == .profile)
        #expect(router.path(.profile) == [.orders, .order(id: "o1")])
    }

    @Test func checkoutOpensOverItsListingOrBundle() {
        signedIn.value = true
        let listingCheckout = AppRoute.checkout(CheckoutTarget(listingId: "l1", offerId: "of1"))
        router.open(.screen(listingCheckout))
        #expect(router.selectedTab == .home)
        #expect(router.path(.home) == [.listing(id: "l1"), listingCheckout])

        let bundleCheckout = AppRoute.checkout(CheckoutTarget(listingId: "l1", bundleId: "b1"))
        router.open(.screen(bundleCheckout))
        #expect(router.selectedTab == .messages)
        #expect(router.path(.messages) == [.bundle(id: "b1"), bundleCheckout])
    }

    @Test func canonicalStacksPutEveryRouteOnATab() {
        let expectations: [(AppRoute, AppTab)] = [
            (.listing(id: "l"), .home), (.member(username: "m"), .home), (.search(ExploreQuery(text: "robe")), .explore),
            (.visualSearch(id: "v"), .explore), (.conversation(id: "c"), .messages), (.bundle(id: "b"), .messages),
            (.favorites, .profile), (.orders, .profile), (.wallet, .profile), (.notifications, .profile),
            (.settings, .profile), (.referrals, .profile), (.myListings, .profile),
        ]
        for (route, tab) in expectations {
            let (canonicalTab, stack) = AppRouter.canonicalStack(for: route)
            #expect(canonicalTab == tab, "\(route)")
            #expect(stack.last == route, "\(route)")
        }
    }

    @Test func tabsOpenAtTheirFirstScreen() {
        router.pathBinding(.messages).wrappedValue = [.conversation(id: "c1")]
        router.open(.inbox)
        #expect(router.selectedTab == .messages)
        #expect(router.path(.messages).isEmpty)

        router.open(.sell)
        #expect(router.selectedTab == .sell)
        router.open(.explore(ExploreQuery()))
        #expect(router.selectedTab == .explore)
        #expect(router.path(.explore).isEmpty)
        router.open(.explore(ExploreQuery(category: "robes")))
        guard case let .search(query, opening)? = router.path(.explore).first, router.path(.explore).count == 1 else {
            Issue.record("Expected the results on the Explore tab")
            return
        }
        #expect(query == ExploreQuery(category: "robes"))
        #expect(opening != nil)
    }

    @Test func aLinkReopensResultsWithTheSameQueryAsAFreshScreen() {
        // The member opened the results of a link, then changed their filters on that screen.
        let link = URL(string: "taleed://categories/women/women-shoes?sort=price_asc")!
        router.open(url: link)
        let first = router.path(.explore)
        router.open(url: link)
        let second = router.path(.explore)
        #expect(first.count == 1 && second.count == 1)
        // A new route identity: the screen starts again from the link's filters.
        #expect(first != second)
        guard case let .search(query, _)? = second.first else {
            Issue.record("Expected the results on the Explore tab")
            return
        }
        #expect(query == ExploreQuery(category: "women-shoes", sort: "price_asc"))

        // Results pushed in the app with the same query differ from the link's too.
        router.popToRoot(.explore)
        router.push(.search(ExploreQuery(category: "women-shoes", sort: "price_asc")))
        let pushed = router.path(.explore)
        router.open(url: link)
        #expect(router.path(.explore) != pushed)
    }

    @Test func otherTabsKeepTheirStacks() {
        router.push(.listing(id: "l1"))
        router.selectedTab = .explore
        router.push(.search(ExploreQuery(text: "zara")))
        router.selectedTab = .home
        #expect(router.path(.home) == [.listing(id: "l1")])
        #expect(router.path(.explore) == [.search(ExploreQuery(text: "zara"))])
    }

    @Test func theOrderUnderItsDisputeThreadIsReachedByGoingBack() {
        router.selectedTab = .profile
        router.push(.orders)
        router.push(.order(id: "o1"))
        router.push(.dispute(id: "d1"))
        router.pushOrGoBack(to: .order(id: "o1"))
        #expect(router.path(.profile) == [.orders, .order(id: "o1")])
    }

    @Test func aThreadReachedByALinkPushesItsOrder() {
        router.selectedTab = .profile
        router.push(.dispute(id: "d1"))
        router.pushOrGoBack(to: .order(id: "o1"))
        #expect(router.path(.profile) == [.dispute(id: "d1"), .order(id: "o1")])
        router.push(.order(id: "o2"))
        router.push(.dispute(id: "d2"))
        router.pushOrGoBack(to: .order(id: "o1"))
        #expect(router.path(.profile).last == .order(id: "o1"))
        #expect(router.path(.profile).count == 5)
    }

    @Test func reselectingTheTabReturnsToItsFirstScreen() {
        router.push(.listing(id: "l1"))
        router.push(.member(username: "amina"))
        router.tabSelection.wrappedValue = .home
        #expect(router.path(.home).isEmpty)
    }

    @Test func signedOutLinkToAPrivateScreenAsksToSignInThenOpensIt() {
        router.open(url: URL(string: "https://taleed.app/wallet")!)
        #expect(router.authEntry == .signIn)
        #expect(router.path(.profile).isEmpty)

        signedIn.value = true
        router.authEntry = nil
        router.authSheetDidDismiss()
        #expect(router.selectedTab == .profile)
        #expect(router.path(.profile) == [.wallet])
    }

    @Test func closingTheSheetSignedOutDropsTheAction() {
        var ran = false
        router.requireSignIn { ran = true }
        #expect(router.authEntry == .signIn)
        router.authEntry = nil
        router.authSheetDidDismiss()
        #expect(!ran)
        // The next sign-in does not run it either.
        signedIn.value = true
        router.authSheetDidDismiss()
        #expect(!ran)
    }

    @Test func signedInActionsRunAtOnce() {
        signedIn.value = true
        var ran = false
        router.requireSignIn { ran = true }
        #expect(ran)
        #expect(router.authEntry == nil)
    }

    @Test func publicScreensOpenSignedOut() {
        router.open(.screen(.member(username: "amina")))
        #expect(router.authEntry == nil)
        #expect(router.path(.home) == [.member(username: "amina")])
        router.open(.screen(.settings))
        #expect(router.path(.profile) == [.settings])
    }

    @Test func inviteLinkOpensSignUpSignedOutAndHomeSignedIn() {
        router.open(url: URL(string: "https://taleed.app/r/a1b2c3d4")!)
        #expect(router.authEntry == .signUp(referralCode: "a1b2c3d4"))

        router.authEntry = nil
        signedIn.value = true
        router.selectedTab = .profile
        router.open(url: URL(string: "https://taleed.app/r/a1b2c3d4")!)
        #expect(router.authEntry == nil)
        #expect(router.selectedTab == .home)
    }

    @Test func listingChatOpensTheConversation() async {
        signedIn.value = true
        router.resolveConversation = { (listingId: String, buyerId: String?) async throws(ApiError) -> String in
            "conversation-\(listingId)-\(buyerId ?? "seller")"
        }
        router.open(.listingChat(listingId: "l1", memberId: "m1"))
        await waitUntil { !router.isResolvingLink }
        #expect(router.selectedTab == .messages)
        #expect(router.path(.messages) == [.conversation(id: "conversation-l1-m1", focusesComposer: true)])
    }

    /// `/listings/{id}/chat` without `?with=`: the buyer's conversation with the seller, signing in first.
    @Test func listingChatAsBuyerSignsInThenOpensTheConversation() async {
        var asked: [String?] = []
        router.resolveConversation = { (listingId: String, buyerId: String?) async throws(ApiError) -> String in
            asked.append(buyerId)
            return "conversation-\(listingId)"
        }
        router.open(url: URL(string: "https://taleed.app/fr/listings/l1/chat")!)
        #expect(router.authEntry == .signIn)
        signedIn.value = true
        router.authSheetDidDismiss()
        await waitUntil { !router.isResolvingLink && router.selectedTab == .messages }
        #expect(asked == [nil])
        #expect(router.path(.messages) == [.conversation(id: "conversation-l1", focusesComposer: true)])
    }

    @Test func listingChatFallsBackToTheListing() async {
        signedIn.value = true
        router.resolveConversation = { (_: String, _: String?) async throws(ApiError) -> String in
            throw .failed(ApiFailure(status: 403, code: .forbidden))
        }
        router.open(.listingChat(listingId: "l1", memberId: "m1"))
        await waitUntil { !router.isResolvingLink }
        #expect(router.selectedTab == .home)
        #expect(router.path(.home) == [.listing(id: "l1")])
    }

    @Test func paymentReturnOpensThePaymentScreenThatSyncs() {
        signedIn.value = true
        router.open(url: URL(string: "taleed://payment-return?kind=order&id=o1&result=success")!)
        #expect(router.path(.profile) == [.orders, .orderPayment(OrderPaymentTarget(orderId: "o1", attempt: .returnedSuccess))])
        #expect(router.consumePaymentReturn(kind: .order, id: "o1") == nil)

        router.open(url: URL(string: "taleed://payment-return?kind=top_up&id=t1&result=failure")!)
        #expect(router.path(.profile) == [.wallet])
        #expect(router.consumePaymentReturn(kind: .topUp, id: "other") == nil)
        #expect(router.consumePaymentReturn(kind: .topUp, id: "t1") == PaymentReturn(kind: .topUp, id: "t1", succeeded: false))
        #expect(router.consumePaymentReturn(kind: .topUp, id: "t1") == nil)
    }

    @Test func checkoutIsReplacedByItsOrdersPaymentScreen() {
        signedIn.value = true
        let checkout = AppRoute.checkout(CheckoutTarget(listingId: "l1"))
        router.open(.screen(checkout))
        let payment = AppRoute.orderPayment(OrderPaymentTarget(orderId: "o1"))
        router.replace(checkout, with: payment)
        #expect(router.path(.home) == [.listing(id: "l1"), payment])
        router.replace(checkout, with: .order(id: "o2"))
        #expect(router.path(.home) == [.listing(id: "l1"), payment, .order(id: "o2")])
    }

    @Test func signOutRemovesPrivateScreensFromTheStacks() {
        signedIn.value = true
        router.open(.screen(.order(id: "o1")))
        router.pathBinding(.home).wrappedValue = [.listing(id: "l1"), .checkout(CheckoutTarget(listingId: "l1"))]
        router.sessionDidEnd()
        #expect(router.path(.profile).isEmpty)
        #expect(router.path(.home) == [.listing(id: "l1")])
    }

    @Test func websitePagesOpenInTheBrowser() {
        var opened: [URL] = []
        router.browser = { opened.append($0) }
        router.websiteLinks = { WebsiteLinks(terms: URL(string: "https://taleed.app/terms")) }
        router.openWebsite(.terms)
        router.openWebsite(.privacy)
        router.openInBrowser(URL(string: "javascript:alert(1)")!)
        #expect(opened == [URL(string: "https://taleed.app/terms")!])
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// Links that come during launch, and the tab selection.
@MainActor
struct AppRouterTabTests {
    @Test func linksWaitForTheLaunch() {
        let router = AppRouter()
        router.open(url: URL(string: "https://taleed.app/listings/l1")!)
        #expect(router.path(.home).isEmpty)
        router.launchWillShowItsScreen()
        #expect(router.path(.home) == [.listing(id: "l1")])
        // Once only: a second call does not open it again.
        router.popToRoot(.home)
        router.launchWillShowItsScreen()
        #expect(router.path(.home).isEmpty)
    }

    /// The tab and its stack change in one mutation, so that no redraw can fall between the two: the shell
    /// never draws the Explore button over Home's content (or the reverse).
    @Test func aLinkSetsItsTabAndStackInOneChange() {
        let router = AppRouter()
        router.launchWillShowItsScreen()
        let changes = ChangeCounter()
        changes.watch { _ = (router.selectedTab, router.path(.explore)) }
        router.open(url: URL(string: "taleed://browse?q=robe")!)
        #expect(changes.count == 1)
        #expect(router.selectedTab == .explore)
        guard case let .search(query, _) = router.path(.explore).first else {
            Issue.record("Explore should show the search results")
            return
        }
        #expect(query.text == "robe")
        #expect(router.path(.explore).count == 1)
    }

    @Test func selectingTheCurrentTabAgainReturnsToItsFirstScreen() {
        let router = AppRouter()
        router.launchWillShowItsScreen()
        router.open(.screen(.listing(id: "l1")))
        router.tabSelection.wrappedValue = .home
        #expect(router.selectedTab == .home)
        #expect(router.path(.home).isEmpty)
        router.push(.listing(id: "l2"))
        router.tabSelection.wrappedValue = .explore
        #expect(router.selectedTab == .explore)
        #expect(router.path(.home) == [.listing(id: "l2")])
    }
}

/// A mutable flag the router's closure reads.
@MainActor
private final class SignedIn {
    var value = false
}

/// Counts the changes of what `read` reads, one per mutation (Observation calls back once per tracking).
@MainActor
final class ChangeCounter {
    private(set) var count = 0

    func watch(_ read: @escaping @MainActor () -> Void) {
        withObservationTracking(read) { [self] in
            MainActor.assumeIsolated {
                count += 1
                watch(read)
            }
        }
    }
}

@MainActor
struct AppRouterSignInTests {
    /// A deletion whose lost answer came back `401`: the session-expired sheet closes, nothing waits.
    @Test func closingSignInForADeletedAccountForgetsTheAction() {
        var isSignedIn = false
        let router = AppRouter()
        router.isSignedIn = { isSignedIn }
        router.launchWillShowItsScreen()
        var ran = false
        router.requireSignIn { ran = true }
        router.closeSignIn()
        #expect(router.authEntry == nil)
        isSignedIn = true
        router.authSheetDidDismiss()
        #expect(!ran)
    }
}
