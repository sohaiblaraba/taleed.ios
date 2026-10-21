import Foundation
@testable import Taleed
import TaleedAPI
import Testing

// MARK: - Fake API

@MainActor
final class FakeNotificationsApi: NotificationsApi {
    /// The pages by cursor (`nil` is the first page); each call takes the next answer for its cursor, the
    /// last one repeating.
    var pages: [String?: [Result<Page<NotificationRow>, Taleed.ApiError>]] = [:]
    var markResults: [Result<UnreadCounts, Taleed.ApiError>] = []
    private(set) var listCalls: [(cursor: String?, automatic: Bool)] = []
    private(set) var markCalls: [String] = []

    func notifications(cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> Page<NotificationRow> {
        listCalls.append((cursor, automatic))
        guard var answers = pages[cursor], !answers.isEmpty else { return Page(items: [], nextCursor: nil, total: 0) }
        let answer = answers.count > 1 ? answers.removeFirst() : answers[0]
        pages[cursor] = answers
        return try answer.get()
    }

    func markNotificationsRead(upTo id: String) async throws(Taleed.ApiError) -> UnreadCounts {
        markCalls.append(id)
        // A cancelled request never reaches the server (URLSession throws).
        if Task.isCancelled { throw .network }
        guard !markResults.isEmpty else { return UnreadCounts(messages: 2, notifications: 0) }
        let result = markResults.count > 1 ? markResults.removeFirst() : markResults[0]
        return try result.get()
    }
}

func notification(_ id: String, type: String = "ORDER_SHIPPED", url: String? = "http://localhost:3000/orders/o1",
                  isRead: Bool = false, minutesAgo: Double = 5) -> NotificationRow {
    NotificationRow(id: id, type: type, text: "Texte \(id)", url: url.flatMap(URL.init(string:)), isRead: isRead,
                    createdAt: Date(timeIntervalSinceNow: -minutesAgo * 60))
}

private func page(_ ids: [String], next: String? = nil, total: Int? = nil) -> Result<Page<NotificationRow>, Taleed.ApiError> {
    .success(Page(items: ids.map { notification($0) }, nextCursor: next, total: total ?? ids.count))
}

private let notFound = Taleed.ApiError.failed(ApiFailure(status: 404, code: .notFound))

// MARK: - Rules

struct NotificationRulesTests {
    @Test func everyTypeOfTheSliceHasItsTheme() {
        let expectations: [(String, NotificationTheme)] = [
            ("NEW_OFFER", .offers), ("OFFER_ACCEPTED", .offers), ("OFFER_ACCEPTED_SELLER", .offers),
            ("OFFER_DECLINED", .offers), ("OFFER_COUNTERED", .offers),
            ("ORDER_PAID", .orders), ("ORDER_SHIPPED_SELLER", .orders), ("ORDER_UNSHIPPED_REFUNDED_SELLER", .orders),
            ("DISPUTE_OPENED", .disputes), ("DISPUTE_RESOLVED", .disputes),
            ("PAYOUT_PAID", .money), ("PAYOUT_REJECTED", .money), ("TOPUP_PAID", .money), ("REFERRAL_REWARD", .money),
            ("VERIFICATION_VOUCHER", .money),
            ("NEW_FAVORITE", .community), ("NEW_FOLLOWER", .community), ("FOLLOWED_MEMBER_LISTED", .community),
            ("REVIEW_RECEIVED", .community), ("REFERRAL_SIGNUP", .community),
            ("VERIFICATION_APPROVED", .account), ("VERIFICATION_REJECTED", .accountIssue), ("REPORT_RESOLVED", .account),
            ("REPORT_DISMISSED", .accountIssue),
            ("BOOST_ACTIVATED", .boosts), ("BOOST_ENDED", .boosts),
        ]
        for (type, theme) in expectations {
            #expect(NotificationTheme(type: type) == theme, "\(type)")
        }
    }

    @Test func anUnknownTypeGetsTheGenericBell() {
        #expect(NotificationTheme(type: "MILESTONE_REACHED") == .other)
        #expect(NotificationTheme(type: "") == .other)
        #expect(NotificationTheme.other.icon == .bell)
        #expect(NotificationTheme(type: "new_offer") == .offers)
    }

    @Test func aRefusalShowsAWarningShieldNotACheck() {
        #expect(NotificationTheme(type: "VERIFICATION_APPROVED").icon == .shieldCheck)
        #expect(NotificationTheme(type: "VERIFICATION_REJECTED").icon == .shieldWarning)
        #expect(NotificationTheme(type: "REPORT_DISMISSED").icon == .shieldWarning)
    }

    @Test func aRowOpensItsLinkThroughTheRouter() {
        #expect(notification("n", url: "http://localhost:3000/orders/o7").destination == .screen(.order(id: "o7")))
        #expect(notification("n", url: "https://taleed.app/ar/wallet").destination == .screen(.wallet))
        #expect(notification("n", url: "http://localhost:3000/listings/l1/chat?with=m2").destination
            == .listingChat(listingId: "l1", memberId: "m2"))
        #expect(notification("n", url: "http://localhost:3000/checkout/l1?offer=of1").destination
            == .screen(.checkout(CheckoutTarget(listingId: "l1", offerId: "of1"))))
        #expect(notification("n", url: "http://localhost:3000/inbox").destination == .inbox)
        // Staff pages go Home, like any path the router does not know.
        #expect(notification("n", url: "http://localhost:3000/admin/payouts").destination == .home)
    }

    @Test func aRowWithoutALinkOrPointingHereIsPlain() {
        #expect(notification("n", url: nil).destination == nil)
        #expect(notification("n", type: "REPORT_RESOLVED", url: "http://localhost:3000/notifications").destination == nil)
        #expect(notification("n", type: "REPORT_DISMISSED", url: "https://taleed.app/fr/notifications").destination == nil)
    }

    @Test func aRoleOfferIsPlain() {
        // Decision 8: staff roles are web-only, so the row has no link (it must not fall to Home).
        #expect(notification("n", type: "ROLE_OFFERED", url: "http://localhost:3000/role-offers").destination == nil)
        #expect(notification("n", type: "role_offered", url: "https://taleed.app/ar/role-offers").destination == nil)
        #expect(notification("n", type: "ROLE_OFFERED", url: nil).destination == nil)
        // A `/role-offers` link stays plain whatever the type says.
        #expect(notification("n", type: "MILESTONE_REACHED", url: "https://taleed.app/en/role-offers").destination == nil)
        #expect(notification("n", type: "ORDER_SHIPPED", url: "http://localhost:3000/role-offers/").destination == nil)
    }

    @MainActor
    @Test func theFeedCountsArrivals() {
        let feed = NotificationsFeed()
        feed.somethingArrived()
        feed.somethingArrived()
        #expect(feed.sequence == 2)
    }
}

// MARK: - View model

@MainActor
struct NotificationsViewModelTests {
    private let api = FakeNotificationsApi()
    private let badges = BadgeRecorder()

    private func makeModel() -> NotificationsViewModel {
        NotificationsViewModel(api: api) { [badges] in badges.counts.append($0) }
    }

    @Test func theFirstPageIsMarkedReadUpToItsFirstRowAndTheBadgesFollow() async {
        api.pages[nil] = [page(["n3", "n2", "n1"])]
        api.markResults = [.success(UnreadCounts(messages: 4, notifications: 0))]
        let model = makeModel()
        await model.loadIfNeeded()
        #expect(model.list.items.map(\.id) == ["n3", "n2", "n1"])
        #expect(api.markCalls == ["n3"])
        #expect(badges.counts == [UnreadCounts(messages: 4, notifications: 0)])
        // The rows keep their unread bar until the next load, as on the website.
        #expect(model.list.items.allSatisfy { !$0.isRead })
    }

    @Test func anEmptyListMarksNothing() async {
        let model = makeModel()
        await model.loadIfNeeded()
        #expect(model.list.isEmpty)
        #expect(!model.isLoadingPastEmptyPages)
        #expect(api.markCalls.isEmpty)
        #expect(badges.counts.isEmpty)
    }

    @Test func anEmptyFirstPageWithMorePagesLoadsOnBeforeTheEmptyState() async {
        api.pages[nil] = [page([], next: "c1")]
        api.pages["c1"] = [page([], next: "c2")]
        api.pages["c2"] = [page(["n5", "n4"])]
        let model = makeModel()
        await model.loadIfNeeded()
        #expect(model.list.items.map(\.id) == ["n5", "n4"])
        #expect(api.listCalls.map(\.cursor) == [nil, "c1", "c2"])
        // Marked with the first row actually shown.
        #expect(api.markCalls == ["n5"])
    }

    @Test func aFailedPageAfterAnEmptyFirstPageOffersRetry() async {
        api.pages[nil] = [page([], next: "c1")]
        api.pages["c1"] = [.failure(.network), page(["n1"])]
        let model = makeModel()
        await model.loadIfNeeded()
        #expect(model.isLoadingPastEmptyPages)
        #expect(model.list.loadMoreError == .network)
        #expect(api.markCalls.isEmpty)
        await model.loadPastEmptyPages()
        #expect(model.list.items.map(\.id) == ["n1"])
        #expect(api.markCalls == ["n1"])
    }

    @Test func pullToRefreshMarksTheNewFirstRowRead() async {
        api.pages[nil] = [page(["n1"]), page(["n2", "n1"])]
        api.markResults = [.success(UnreadCounts(messages: 0, notifications: 0)), .success(UnreadCounts(messages: 1, notifications: 0))]
        let model = makeModel()
        await model.loadIfNeeded()
        await model.refresh()
        #expect(model.list.items.map(\.id) == ["n2", "n1"])
        #expect(api.markCalls == ["n1", "n2"])
        #expect(badges.counts.last == UnreadCounts(messages: 1, notifications: 0))
    }

    /// Pull-to-refresh cancels its task once the first page is on screen: the mark-read still goes.
    @Test func markReadSurvivesTheCancelledRefreshTask() async {
        api.pages[nil] = [page(["n1"])]
        let model = makeModel()
        let task = Task { await model.refresh() }
        task.cancel()
        await task.value
        #expect(api.markCalls == ["n1"])
        #expect(badges.counts == [UnreadCounts(messages: 2, notifications: 0)])
    }

    @Test func aQuietReloadIsAutomaticAndMarksReadAgain() async {
        api.pages[nil] = [page(["n1"]), page(["n2", "n1"])]
        let model = makeModel()
        await model.loadIfNeeded()
        await model.reloadQuietly()
        #expect(api.listCalls.map(\.automatic) == [false, true])
        #expect(api.markCalls == ["n1", "n2"])
    }

    @Test func aQuietReloadBeforeTheFirstLoadIsTheFirstLoad() async {
        api.pages[nil] = [page(["n1"])]
        let model = makeModel()
        await model.reloadQuietly()
        #expect(model.list.items.map(\.id) == ["n1"])
        #expect(api.markCalls == ["n1"])
    }

    @Test func notFoundOnMarkReadReloadsTheListOnce() async {
        api.pages[nil] = [page(["gone"]), page(["n2", "n1"])]
        api.markResults = [.failure(notFound), .success(UnreadCounts(messages: 0, notifications: 0))]
        let model = makeModel()
        await model.loadIfNeeded()
        #expect(model.list.items.map(\.id) == ["n2", "n1"])
        #expect(api.markCalls == ["gone", "n2"])
        #expect(badges.counts == [UnreadCounts(messages: 0, notifications: 0)])
    }

    @Test func notFoundTwiceInARowStopsReloading() async {
        api.pages[nil] = [page(["n1"])]
        api.markResults = [.failure(notFound)]
        let model = makeModel()
        await model.loadIfNeeded()
        #expect(api.markCalls == ["n1", "n1"])
        #expect(api.listCalls.count == 2)
        #expect(badges.counts.isEmpty)
    }

    @Test func aFailedMarkReadIsQuiet() async {
        api.pages[nil] = [page(["n1"])]
        api.markResults = [.failure(.network)]
        let model = makeModel()
        await model.loadIfNeeded()
        #expect(model.list.items.map(\.id) == ["n1"])
        #expect(model.list.error == nil)
        #expect(api.markCalls == ["n1"])
        #expect(api.listCalls.count == 1)
        #expect(badges.counts.isEmpty)
    }

    @Test func aFailedFirstPageShowsTheErrorThenRetryMarksRead() async {
        api.pages[nil] = [.failure(.network), page(["n1"])]
        let model = makeModel()
        await model.loadIfNeeded()
        #expect(model.list.error == .network)
        #expect(api.markCalls.isEmpty)
        await model.retry()
        #expect(model.list.error == nil)
        #expect(api.markCalls == ["n1"])
    }

    @Test func aFailedFirstPageLeavesTheBadgesAlone() async {
        api.pages[nil] = [.failure(.network)]
        let model = makeModel()
        await model.loadIfNeeded()
        #expect(model.list.error == .network)
        // The bell keeps its last known count: nothing is sent to the badges.
        #expect(badges.counts.isEmpty)
    }

    @Test func pagesAreDeduplicatedById() async {
        api.pages[nil] = [page(["n4", "n3"], next: "c1", total: 4)]
        api.pages["c1"] = [page(["n3", "n2", "n1"], total: 4)]
        let model = makeModel()
        await model.loadIfNeeded()
        await model.list.loadMore()
        #expect(model.list.items.map(\.id) == ["n4", "n3", "n2", "n1"])
        #expect(!model.list.hasMore)
        // Scrolling down marks nothing more.
        #expect(api.markCalls == ["n4"])
    }
}

@MainActor
private final class BadgeRecorder {
    var counts: [UnreadCounts] = []
}

// MARK: - Opening a row

@MainActor
struct NotificationLinkRoutingTests {
    private let router = AppRouter()

    init() {
        router.isSignedIn = { true }
        router.launchWillShowItsScreen()
    }

    @Test func aScreenGoesOnTopOfTheNotifications() {
        router.selectedTab = .home
        router.push(.notifications)
        router.openFromScreen(.screen(.order(id: "o1")))
        #expect(router.selectedTab == .home)
        #expect(router.path(.home) == [.notifications, .order(id: "o1")])
    }

    @Test func theScreenAlreadyOnTopStays() {
        router.selectedTab = .profile
        router.push(.notifications)
        router.openFromScreen(.screen(.notifications))
        #expect(router.path(.profile) == [.notifications])
    }

    @Test func aTabOpensAsALinkDoes() {
        router.selectedTab = .home
        router.push(.notifications)
        router.openFromScreen(.inbox)
        #expect(router.selectedTab == .messages)
        #expect(router.path(.messages).isEmpty)
        #expect(router.path(.home) == [.notifications])
    }

    @Test func aNewFavoriteOpensTheSellersConversationOverTheNotifications() async {
        router.resolveConversation = { (listingId: String, buyerId: String?) async throws(Taleed.ApiError) -> String in
            "c-\(listingId)-\(buyerId ?? "")"
        }
        router.selectedTab = .home
        router.push(.notifications)
        router.openFromScreen(.listingChat(listingId: "l1", memberId: "m2"))
        await waitUntil { !router.isResolvingLink }
        #expect(router.path(.home) == [.notifications, .conversation(id: "c-l1-m2", focusesComposer: true)])
    }

    @Test func aConversationThatCannotOpenFallsBackToTheListing() async {
        router.resolveConversation = { (_: String, _: String?) async throws(Taleed.ApiError) -> String in
            throw .failed(ApiFailure(status: 403, code: .forbidden))
        }
        router.selectedTab = .profile
        router.push(.notifications)
        router.openFromScreen(.listingChat(listingId: "l1", memberId: "m2"))
        await waitUntil { !router.isResolvingLink }
        #expect(router.path(.profile) == [.notifications, .listing(id: "l1")])
    }

    @Test func aNotificationsLinkTellsTheOpenScreen() {
        var opened = 0
        router.onNotificationsOpened = { opened += 1 }
        router.open(url: URL(string: "http://localhost:3000/notifications")!)
        #expect(router.selectedTab == .profile)
        #expect(router.path(.profile) == [.notifications])
        #expect(opened == 1)
        router.open(.screen(.wallet))
        #expect(opened == 1)
    }
}
