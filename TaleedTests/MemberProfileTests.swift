import Foundation
@testable import Taleed
import Testing

extension Taleed.MemberProfile {
    static func fixture(username: String = "amina", isMe: Bool = false, isFollowing: Bool = false, isBlocked: Bool = false,
                        canBundle: Bool = true, followersCount: Int = 15,
                        categories: [Taleed.WardrobeCategory] = MemberFixtures.categories) -> Taleed.MemberProfile {
        Taleed.MemberProfile(
            id: "id-\(username)", username: username, displayName: "@\(username)", avatarURL: nil, isVerified: false,
            isOfficial: false, bio: "Je vide mon dressing", wilaya: CatalogWilaya(id: 16, name: "Alger"),
            memberSince: Date(timeIntervalSince1970: 1_790_000_000), lastSeenAt: nil, isOnline: true,
            rating: MemberRating(average: 5, count: 1), salesCount: 1, followersCount: followersCount, followingCount: 6,
            checks: MemberChecks(email: true, phone: false, identity: false), isMe: isMe, isFollowing: isFollowing,
            isBlocked: isBlocked, canBundle: canBundle, openBundleId: nil, wardrobeTotal: categories.reduce(0) { $0 + $1.count },
            wardrobeCategories: categories, shareURL: URL(string: "https://taleed.app/members/\(username)")
        )
    }
}

/// A `MembersApi` answering from canned results, recording its calls.
@MainActor
final class FakeMembersApi: MembersApi {
    var profiles: [Result<Taleed.MemberProfile, Taleed.ApiError>] = []
    var profile: Result<Taleed.MemberProfile, Taleed.ApiError> = .success(.fixture())
    var wardrobePage: Result<Page<ListingSummary>, Taleed.ApiError> = .success(Page(items: [.fixture()], nextCursor: nil, total: 1))
    var reviewsPage: Result<Page<MemberReview>, Taleed.ApiError> = .success(Page(items: [], nextCursor: nil, total: 0))
    var follow: Result<FollowResult, Taleed.ApiError> = .success(FollowResult(isFollowing: true, followersCount: 16))
    var blockResult: Result<Void, Taleed.ApiError> = .success(())
    private(set) var memberCalls: [(username: String, automatic: Bool)] = []
    private(set) var wardrobeCalls: [(username: String, query: WardrobeQuery)] = []
    private(set) var followCalls: [Bool] = []
    private(set) var blockCalls: [Bool] = []
    private(set) var reviewsCalls = 0

    func member(username: String, automatic: Bool) async throws(Taleed.ApiError) -> Taleed.MemberProfile {
        memberCalls.append((username, automatic))
        if !profiles.isEmpty { return try profiles.removeFirst().get() }
        return try profile.get()
    }

    func wardrobe(username: String, query: WardrobeQuery, cursor: String?, automatic: Bool) async throws(Taleed.ApiError)
        -> Page<ListingSummary> {
        wardrobeCalls.append((username, query))
        return try wardrobePage.get()
    }

    func reviews(username: String, cursor: String?, automatic: Bool) async throws(Taleed.ApiError) -> Page<MemberReview> {
        reviewsCalls += 1
        return try reviewsPage.get()
    }

    func setFollowing(username: String, following: Bool) async throws(Taleed.ApiError) -> FollowResult {
        followCalls.append(following)
        return try follow.get()
    }

    func setBlocked(username: String, blocked: Bool) async throws(Taleed.ApiError) {
        blockCalls.append(blocked)
        try blockResult.get()
    }
}

enum MemberFixtures {
    static let categories = [
        Taleed.WardrobeCategory(id: "cat-women-clothes", slug: "women-clothes", name: "Vêtements", parentName: "Femmes", count: 3),
        Taleed.WardrobeCategory(id: "cat-kids-clothes", slug: "kids-clothes", name: "Vêtements", parentName: "Enfants", count: 1),
        Taleed.WardrobeCategory(id: "cat-women-bags", slug: "women-bags", name: "Sacs", parentName: "Femmes", count: 2),
    ]
}

@MainActor
struct MemberProfileTests {
    static let categories = MemberFixtures.categories

    private let api = FakeMembersApi()

    // MARK: Actions from the server's flags

    @Test func anotherMemberOffersFollowBundleBlockAndReport() {
        let actions = MemberProfileActions(profile: .fixture())
        #expect(actions.primary == .follow(following: false))
        #expect(actions.showsShopBundle && actions.showsBlockMenu && actions.showsReport)
        #expect(!actions.showsBlockedNotice)
        #expect(MemberProfileActions(profile: .fixture(isFollowing: true)).primary == .follow(following: true))
    }

    @Test func aBlockedMemberShowsUnblockInsteadOfFollowAndNoBundle() {
        // The API already says `canBundle: false` across a block; the app hides it whatever the flag says.
        let actions = MemberProfileActions(profile: .fixture(isFollowing: false, isBlocked: true, canBundle: true))
        #expect(actions.primary == .unblock)
        #expect(!actions.showsShopBundle)
        #expect(actions.showsBlockedNotice && actions.showsReport && actions.showsBlockMenu)
    }

    @Test func theOwnProfileHasEditAndNoFollowBlockOrReport() {
        let actions = MemberProfileActions(profile: .fixture(isMe: true, canBundle: false))
        #expect(actions.primary == .ownProfile)
        #expect(!actions.showsBlockMenu && !actions.showsReport && !actions.showsShopBundle && !actions.showsBlockedNotice)
    }

    @Test func theOfficialAccountCannotBeBlockedButCanBeReported() {
        var official = Taleed.MemberProfile.fixture(username: "taleed", canBundle: false)
        official = Taleed.MemberProfile(
            id: official.id, username: official.username, displayName: official.displayName, avatarURL: nil, isVerified: true,
            isOfficial: true, bio: nil, wilaya: nil, memberSince: official.memberSince, lastSeenAt: nil, isOnline: false,
            rating: nil, salesCount: 0, followersCount: 0, followingCount: 0, checks: official.checks, isMe: false,
            isFollowing: false, isBlocked: false, canBundle: false, openBundleId: nil, wardrobeTotal: 0,
            wardrobeCategories: [], shareURL: nil
        )
        let actions = MemberProfileActions(profile: official)
        #expect(!actions.showsBlockMenu)
        #expect(actions.showsReport)
        #expect(actions.primary == .follow(following: false))
    }

    @Test func bundleFollowsTheServerFlag() {
        #expect(!MemberProfileActions(profile: .fixture(canBundle: false)).showsShopBundle)
    }

    @Test func memberTextTakesTheDirectionOfItsFirstLetter() {
        #expect("Je vide mon dressing !".naturalLayoutDirection == .leftToRight)
        #expect("  أبيع ملابسي".naturalLayoutDirection == .rightToLeft)
        #expect("2024 — Zara".naturalLayoutDirection == .leftToRight)
        #expect("123 👍".naturalLayoutDirection == nil)
    }

    // MARK: Wardrobe filter

    @Test func sharedNamesShowTheirParent() {
        let labels = Self.categories.map { WardrobeFilterRules.label(for: $0, among: Self.categories) }
        #expect(labels == ["Vêtements · Femmes", "Vêtements · Enfants", "Sacs"])
    }

    @Test func categoriesAreSortedByLabel() {
        let sorted = WardrobeFilterRules.sorted(Self.categories, locale: Locale(identifier: "fr"))
        #expect(sorted.map(\.slug) == ["women-bags", "kids-clothes", "women-clothes"])
    }

    @Test func theCategoryPickerShowsFromTwoCategories() {
        #expect(WardrobeFilterRules.showsCategoryPicker(Self.categories))
        #expect(!WardrobeFilterRules.showsCategoryPicker(Array(Self.categories.prefix(1))))
        #expect(!WardrobeFilterRules.showsCategoryPicker([]))
    }

    @Test func showResultsCountsTheChosenCategory() {
        #expect(WardrobeFilterRules.count(for: nil, total: 6, categories: Self.categories) == 6)
        #expect(WardrobeFilterRules.count(for: "women-bags", total: 6, categories: Self.categories) == 2)
        #expect(WardrobeFilterRules.count(for: "unknown", total: 6, categories: Self.categories) == 0)
        // A website link names the category by its id.
        #expect(WardrobeFilterRules.count(for: "cat-women-bags", total: 6, categories: Self.categories) == 2)
    }

    @Test func aLinkCategoryIdIsKeptAndGoesToTheApiAsItIs() async {
        let byId = WardrobeQuery(category: "cat-women-bags", sort: .newest)
        #expect(WardrobeFilterRules.sanitized(byId, categories: Self.categories) == byId)
        let model = MemberProfileViewModel(username: "amina", wardrobe: byId, api: api)
        let first = model.wardrobe
        await model.loadIfNeeded()
        // Not dropped, and the list that loaded with it stays (no second load).
        #expect(model.wardrobeQuery == byId)
        #expect(model.wardrobe === first)
        #expect(api.wardrobeCalls.map(\.query) == [byId])
        #expect(model.wardrobeCount == 2)
    }

    @Test func aLinkCategoryTheMemberDoesNotSellInIsDropped() {
        let query = WardrobeQuery(category: "cmveeamsr00009gq3xfxjkis3", sort: .priceAsc)
        #expect(WardrobeFilterRules.sanitized(query, categories: Self.categories) == WardrobeQuery(category: nil, sort: .priceAsc))
        let valid = WardrobeQuery(category: "women-bags", sort: .newest)
        #expect(WardrobeFilterRules.sanitized(valid, categories: Self.categories) == valid)
        #expect(!WardrobeQuery().isFiltered)
        #expect(WardrobeQuery(sort: .priceDesc).isFiltered)
    }

    @Test func applyingAFilterStartsANewWardrobe() async {
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        let first = model.wardrobe
        model.applyWardrobe(WardrobeQuery(category: "women-bags", sort: .priceAsc))
        #expect(model.wardrobe !== first)
        await model.wardrobe.loadIfNeeded()
        #expect(api.wardrobeCalls.last?.query == WardrobeQuery(category: "women-bags", sort: .priceAsc))
        #expect(model.wardrobeCount == 2)
        // The same filter again keeps the list.
        let current = model.wardrobe
        model.applyWardrobe(WardrobeQuery(category: "women-bags", sort: .priceAsc))
        #expect(model.wardrobe === current)
    }

    // MARK: Loading

    @Test func aFormerUsernameIsReplacedByTheCurrentOne() async {
        api.profile = .success(.fixture(username: "amina.b"))
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        #expect(model.username == "amina.b")
        await model.reload()
        #expect(api.memberCalls.map(\.username) == ["amina", "amina.b"])
    }

    @Test func aSuspendedMemberIsNoLongerAvailable() async {
        api.profile = .failure(apiError(404, "not_found"))
        let model = MemberProfileViewModel(username: "ghost", api: api)
        await model.loadIfNeeded()
        #expect(model.profile == nil)
        #expect(model.loadError?.isNotFound == true)
    }

    @Test func aFailedFirstLoadOffersRetry() async {
        api.profiles = [.failure(.network), .success(.fixture())]
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        #expect(model.loadError == .network)
        await model.retry()
        #expect(model.loadError == nil && model.profile != nil)
    }

    @Test func returningAfterAWhileReloadsQuietly() async {
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        let start = ContinuousClock.now
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(10))
        #expect(api.memberCalls.count == 1)
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(61))
        #expect(api.memberCalls.map(\.automatic) == [false, true])
    }

    @Test func returningAfterAWhileRefreshesTheReviewsOnScreen() async {
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        model.tab = .reviews
        await model.reviews.loadIfNeeded()
        #expect(api.reviewsCalls == 1)
        let start = ContinuousClock.now
        model.wentToBackground(at: start)
        await model.returnedToForeground(at: start + .seconds(61))
        #expect(api.reviewsCalls == 2)
        // The wardrobe, not on screen, waits.
        #expect(api.wardrobeCalls.count == 1)
    }

    // MARK: Bundle link (`?bundle=1`)

    @Test func aBundleLinkOpensTheBuilderOnceWhenTheProfileOffersIt() async {
        let model = MemberProfileViewModel(username: "amina", opensBundle: true, api: api)
        #expect(!model.takeBundleRequest())
        await model.loadIfNeeded()
        #expect(model.takeBundleRequest())
        #expect(!model.takeBundleRequest())
    }

    @Test func aBundleLinkStaysOnTheProfileWhenItIsOwnOrBlocked() async {
        for profile in [Taleed.MemberProfile.fixture(isMe: true, canBundle: false), .fixture(isBlocked: true, canBundle: false),
                        .fixture(canBundle: false)] {
            api.profile = .success(profile)
            let model = MemberProfileViewModel(username: "amina", opensBundle: true, api: api)
            await model.loadIfNeeded()
            #expect(!model.takeBundleRequest())
        }
        let plain = MemberProfileViewModel(username: "amina", api: api)
        api.profile = .success(.fixture())
        await plain.loadIfNeeded()
        #expect(!plain.takeBundleRequest())
    }

    // MARK: Follow and block

    @Test func followTakesTheCountFromTheAnswer() async {
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        #expect(await model.toggleFollow() == .done)
        #expect(api.followCalls == [true])
        #expect(model.profile?.isFollowing == true && model.profile?.followersCount == 16)
        api.follow = .success(FollowResult(isFollowing: false, followersCount: 15))
        _ = await model.toggleFollow()
        #expect(api.followCalls == [true, false])
        #expect(model.profile?.isFollowing == false && model.profile?.followersCount == 15)
    }

    @Test func followBlockedReloadsTheProfile() async {
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        api.follow = .failure(apiError(403, "blocked"))
        let outcome = await model.toggleFollow()
        #expect(outcome == .failed(apiError(403, "blocked")))
        #expect(api.memberCalls.count == 2)
    }

    @Test func noFollowOnTheOwnProfileOrABlockedOne() async {
        api.profile = .success(.fixture(isMe: true))
        let own = MemberProfileViewModel(username: "amina", api: api)
        await own.loadIfNeeded()
        _ = await own.toggleFollow()
        api.profile = .success(.fixture(isBlocked: true))
        let blocked = MemberProfileViewModel(username: "amina", api: api)
        await blocked.loadIfNeeded()
        _ = await blocked.toggleFollow()
        #expect(api.followCalls.isEmpty)
    }

    @Test func blockingReloadsTheProfileSoItsFlagsApply() async {
        api.profiles = [.success(.fixture(isFollowing: true)), .success(.fixture(isFollowing: false, isBlocked: true, canBundle: false))]
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        #expect(await model.block() == .blocked("@amina"))
        #expect(api.blockCalls == [true])
        #expect(model.actions?.primary == .unblock)
        #expect(model.actions?.showsShopBundle == false)
    }

    @Test func unblockingDoesNotBringTheFollowBack() async {
        api.profiles = [.success(.fixture(isBlocked: true)), .success(.fixture(isFollowing: false, isBlocked: false))]
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        #expect(await model.unblock() == .unblocked("@amina"))
        #expect(api.blockCalls == [false])
        #expect(model.actions?.primary == .follow(following: false))
    }

    @Test func blockingTheOfficialAccountFailsWithItsMessage() async {
        let model = MemberProfileViewModel(username: "taleed", api: api)
        await model.loadIfNeeded()
        api.blockResult = .failure(apiError(403, "forbidden"))
        #expect(await model.block() == .failed(apiError(403, "forbidden")))
    }

    // MARK: Sign-in in the middle of an action

    @Test func followAfterSigningInRunsOnlyWhenStillOffered() async {
        api.profiles = [.success(.fixture()), .success(.fixture(isFollowing: true))]
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        // Already following once signed in: nothing left to do.
        #expect(await model.resolvePending(.follow, memberId: "yasmine") == nil)
    }

    @Test func actionsOnTheOwnProfileAreDroppedAfterSigningIn() async {
        api.profiles = [.success(.fixture()), .success(.fixture(isMe: true))]
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        #expect(await model.resolvePending(.report, memberId: "amina") == nil)
        api.profile = .success(.fixture())
        await model.memberDidChange(to: "karim")
        #expect(await model.resolvePending(.report, memberId: "karim") == .report)
        #expect(await model.resolvePending(.block, memberId: "karim") == .block)
        #expect(await model.resolvePending(.follow, memberId: "karim") == .follow)
    }
}

/// The member's own profile after they changed a listing elsewhere (G8).
@MainActor
struct MemberProfileListingChangesTests {
    private let api = FakeMembersApi()

    /// Own profile → My listings → hide or edit → Back: the profile and the wardrobe again (G8).
    @Test func theOwnProfileReloadsWhenShownAfterAListingChanged() async {
        api.profile = .success(.fixture(isMe: true, canBundle: false))
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        await model.appeared()
        #expect(api.memberCalls.count == 1)
        model.disappeared()
        await model.listingsChanged()
        #expect(api.memberCalls.count == 1)
        await model.appeared()
        #expect(api.memberCalls.map(\.automatic) == [false, true])
        #expect(api.wardrobeCalls.count == 2)
        // Once per change.
        model.disappeared()
        await model.appeared()
        #expect(api.memberCalls.count == 2)
        // Back before the answer came: the change lands while the profile shows.
        await model.listingsChanged()
        #expect(api.memberCalls.count == 3)
    }

    @Test func anotherMembersProfileIgnoresTheMembersListingChanges() async {
        let model = MemberProfileViewModel(username: "amina", api: api)
        await model.loadIfNeeded()
        await model.appeared()
        await model.listingsChanged()
        #expect(api.memberCalls.count == 1)
    }
}
