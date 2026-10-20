import Foundation
@testable import Taleed
import Testing

/// Every path of screens.md §1.2 (slice-d.md and slice-e.md "Opening links and pushes").
struct LinkRouterTests {
    private func destination(_ link: String) -> AppDestination {
        LinkRouter.destination(for: link)
    }

    @Test(arguments: [
        ("https://taleed.app/listings/abc123", AppDestination.screen(.listing(id: "abc123"))),
        ("https://taleed.app/members/amina", .screen(.member(username: "amina"))),
        ("https://taleed.app/visual-search/vs1", .screen(.visualSearch(id: "vs1"))),
        ("https://taleed.app/sell", .sell),
        ("https://taleed.app/favorites", .screen(.favorites)),
        ("https://taleed.app/inbox", .inbox),
        ("https://taleed.app/inbox/conv1", .screen(.conversation(id: "conv1"))),
        ("https://taleed.app/bundle/b1", .screen(.bundle(id: "b1"))),
        ("https://taleed.app/orders", .screen(.orders)),
        ("https://taleed.app/orders/o1", .screen(.order(id: "o1"))),
        ("https://taleed.app/wallet", .screen(.wallet)),
        ("https://taleed.app/notifications", .screen(.notifications)),
        ("https://taleed.app/settings", .screen(.settings)),
        ("https://taleed.app/referrals", .screen(.referrals)),
        ("https://taleed.app/r/a1b2c3d4", .signUp(referralCode: "a1b2c3d4")),
        ("https://taleed.app/", .home),
        ("https://taleed.app", .home),
    ])
    func paths(link: String, expected: AppDestination) {
        #expect(destination(link) == expected)
    }

    @Test func listingChatOpensTheConversationWithTheMember() {
        #expect(destination("https://taleed.app/listings/l1/chat?with=m2") == .listingChat(listingId: "l1", memberId: "m2"))
    }

    /// The edit form is reached in the app only (the website's edit page goes Home, screens.md §1.2);
    /// it sits over the listing and needs a session.
    @MainActor @Test func theEditFormSitsOverTheListing() {
        #expect(AppRoute.editListing(id: "l1").requiresSignIn)
        #expect(AppRouter.canonicalStack(for: .editListing(id: "l1")) == (.home, [.listing(id: "l1"), .editListing(id: "l1")]))
    }

    /// Without `?with=` the member writes to the seller as a buyer (the website's `getOrCreateConversation`).
    @Test func listingChatWithoutMemberOpensTheBuyersConversation() {
        #expect(destination("https://taleed.app/listings/l1/chat") == .listingChat(listingId: "l1", memberId: nil))
        #expect(destination("https://taleed.app/listings/l1/chat?with=") == .listingChat(listingId: "l1", memberId: nil))
        #expect(destination("taleed://listings/l1/chat") == .listingChat(listingId: "l1", memberId: nil))
    }

    @Test func checkoutCarriesOfferAndBundle() {
        #expect(destination("https://taleed.app/checkout/l1") == .screen(.checkout(CheckoutTarget(listingId: "l1"))))
        #expect(destination("https://taleed.app/checkout/l1?offer=of1")
            == .screen(.checkout(CheckoutTarget(listingId: "l1", offerId: "of1"))))
        #expect(destination("https://taleed.app/checkout/l1?bundle=b1")
            == .screen(.checkout(CheckoutTarget(listingId: "l1", bundleId: "b1"))))
    }

    @Test func browseKeepsEveryFilter() {
        let link = "https://taleed.app/browse?q=robe%20zara&category=femmes&brand=zara&wilaya=16&condition=VERY_GOOD"
            + "&size=M&minPrice=500&maxPrice=3000&sort=newest"
        let expected = ExploreQuery(text: "robe zara", category: "femmes", brand: "zara", wilaya: 16, condition: "VERY_GOOD",
                                    size: "M", minPrice: 500, maxPrice: 3000, sort: "newest")
        #expect(destination(link) == .explore(expected))
    }

    @Test func browseWithoutFiltersIsExplore() {
        #expect(destination("https://taleed.app/browse") == .explore(ExploreQuery()))
    }

    @Test func browseDropsValuesItCannotRead() {
        #expect(destination("https://taleed.app/browse?wilaya=algiers&minPrice=&q=%20") == .explore(ExploreQuery()))
    }

    @Test func categoriesUseTheLastSlug() {
        #expect(destination("https://taleed.app/categories/femmes") == .explore(ExploreQuery(category: "femmes")))
        #expect(destination("https://taleed.app/categories/femmes/robes") == .explore(ExploreQuery(category: "robes")))
        #expect(destination("https://taleed.app/categories/femmes/robes?sort=price_asc")
            == .explore(ExploreQuery(category: "robes", sort: "price_asc")))
    }

    @Test(arguments: ["ar", "en", "fr"])
    func languagePrefixIsStripped(prefix: String) {
        #expect(destination("https://taleed.app/\(prefix)/listings/abc") == .screen(.listing(id: "abc")))
        #expect(destination("https://taleed.app/\(prefix)/inbox/c1") == .screen(.conversation(id: "c1")))
        #expect(destination("https://taleed.app/\(prefix)") == .home)
    }

    @Test(arguments: [
        "https://taleed.app/admin",
        "https://taleed.app/admin/orders/o1",
        "https://taleed.app/role-offers",
        "https://taleed.app/terms",
        "https://taleed.app/guides/vendre",
        "https://taleed.app/listings",
        "https://taleed.app/listings/l1/edit",
        "taleed://listings/l1/edit",
        "https://taleed.app/listings/l1/extra",
        "https://taleed.app/listings/l1/edit/more",
        "https://taleed.app/orders/o1/extra",
        "https://taleed.app/r",
        "https://taleed.app/members",
        "https://taleed.app/categories",
        "https://taleed.app/sell/extra",
        "mailto:contact@taleed.app",
        "",
    ])
    func anythingElseIsHome(link: String) {
        #expect(destination(link) == .home)
    }

    @Test func taleedHostsRouteOnThePath() {
        // Pushes carry the server's own address: localhost locally (Debug), staging on staging.
        #expect(destination("http://localhost:3000/orders/o1") == .screen(.order(id: "o1")))
        #expect(destination("https://staging.taleed.app/en/wallet") == .screen(.wallet))
        #expect(destination("https://www.taleed.app/listings/l1") == .screen(.listing(id: "l1")))
        #expect(destination("https://TALEED.app/orders") == .screen(.orders))
    }

    /// Another host opens in the in-app browser, never a screen by its path (Android's `AppDestination.Web`).
    @Test func otherHostsOpenInTheBrowser() throws {
        let external = try #require(URL(string: "https://example.com/listings/1"))
        #expect(LinkRouter.destination(for: external) == .web(external))
        let help = try #require(URL(string: "https://help.example.org/guide?x=1"))
        #expect(LinkRouter.destination(for: help) == .web(help))
        #expect(destination("https://taleed.app.example.com/orders") != .screen(.orders))
    }

    @Test func pathsWithoutHostRoute() {
        #expect(destination("/listings/l1") == .screen(.listing(id: "l1")))
        #expect(destination("/ar/notifications") == .screen(.notifications))
    }

    @Test func trailingSlashesAndEncodingAreTolerated() {
        #expect(destination("https://taleed.app/orders/") == .screen(.orders))
        #expect(destination("https://taleed.app/members/%40amina") == .screen(.member(username: "amina")))
    }

    @Test func memberLinksKeepTheWardrobeFilterAndTheBundleMode() {
        #expect(destination("https://taleed.app/ar/members/amina?category=women-bags&sort=price_asc")
            == .screen(.member(username: "amina", wardrobe: WardrobeQuery(category: "women-bags", sort: .priceAsc))))
        // An unknown sort is the default one.
        #expect(destination("/members/amina?sort=cheapest") == .screen(.member(username: "amina")))
        // The website's "Achète en lot" link opens the profile, which opens the builder when it offers it.
        #expect(destination("/members/amina?bundle=1") == .screen(.member(username: "amina", opensBundle: true)))
        #expect(destination("/members/amina?bundle=0") == .screen(.member(username: "amina")))
        // The website's links carry the category's id.
        #expect(destination("/members/amina?category=cmveeamt8000o9gq3p2reista")
            == .screen(.member(username: "amina", wardrobe: WardrobeQuery(category: "cmveeamt8000o9gq3p2reista"))))
        #expect(destination("/members/") == .home)
        #expect(destination("/members/amina/extra") == .home)
    }

    @Test func paymentReturn() {
        #expect(destination("taleed://payment-return?kind=order&id=o1&result=success")
            == .paymentReturn(PaymentReturn(kind: .order, id: "o1", succeeded: true)))
        #expect(destination("taleed://payment-return?kind=top_up&id=t1&result=failure")
            == .paymentReturn(PaymentReturn(kind: .topUp, id: "t1", succeeded: false)))
        #expect(destination("taleed://payment-return?kind=boost&id=x&result=success") == .home)
        #expect(destination("taleed://payment-return?kind=order&result=success") == .home)
    }

    @Test func appSchemeReadsLikeAPath() {
        #expect(destination("taleed://listings/l1") == .screen(.listing(id: "l1")))
        #expect(destination("taleed://inbox") == .inbox)
        #expect(destination("otherapp://listings/l1") == .home)
    }
}
