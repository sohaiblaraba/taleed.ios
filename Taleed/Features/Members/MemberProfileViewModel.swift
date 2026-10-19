import Foundation
import Observation

/// The member profile (screens.md §2 G5 and §7 G5): the profile, the wardrobe with its filter, the
/// reviews, and the viewer's actions (follow, block, unblock). Kept while the screen is in the stack.
///
/// Actions return what happened; the screen shows the toast and navigates. Permissions come from the
/// server's flags (`MemberProfileActions`).
@MainActor
@Observable
final class MemberProfileViewModel {
    enum Tab: Int, CaseIterable, Sendable {
        case wardrobe, reviews
    }

    /// What a member started signed out, run once signed in when the reloaded profile still offers it
    /// (screens.md §0.5).
    enum PendingAction: Equatable, Sendable {
        case follow, block, report, shopBundle
    }

    enum Outcome: Equatable {
        case done
        /// Blocked or unblocked; the profile was reloaded. Carries the handle for the toast.
        case blocked(String)
        case unblocked(String)
        /// It failed: show the message. The profile was reloaded when the error says it changed.
        case failed(ApiError)
    }

    enum Work: Hashable, Sendable {
        case follow, block
    }

    /// The username to ask for: the link's at first, then the one the API answers (a former username
    /// leads to the current one).
    private(set) var username: String
    private(set) var profile: MemberProfile?
    /// The first load failed (`404`: "no longer available").
    private(set) var loadError: ApiError?
    /// A reload the member asked for failed while the profile stays on screen: a toast.
    private(set) var refreshError: ApiError?
    private(set) var running: Set<Work> = []
    var tab: Tab = .wardrobe
    private(set) var wardrobeQuery: WardrobeQuery
    /// A new list for each filter, so that a filter never shows the previous one's cards.
    private(set) var wardrobe: PagedList<ListingSummary>
    private(set) var reviews: PagedList<MemberReview>

    @ObservationIgnored private let api: MembersApi
    @ObservationIgnored private let origin = MemberRequestOrigin()
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var memberId: String?
    /// The member the profile on screen was loaded for (nil signed out): its flags are theirs.
    @ObservationIgnored private var loadedFor: String??
    @ObservationIgnored private var backgroundSince: ContinuousClock.Instant?

    /// A shorter absence keeps the screen as it is (as the listing screen).
    static let foregroundReloadAfter: Duration = .seconds(60)

    init(username: String, wardrobe query: WardrobeQuery = WardrobeQuery(), api: MembersApi, memberId: String? = nil) {
        self.username = username
        self.api = api
        self.memberId = memberId
        wardrobeQuery = query
        // Placeholders replaced below, once `self` exists for the closures.
        wardrobe = PagedList { _ throws(ApiError) in Page(items: [], nextCursor: nil, total: 0) }
        reviews = PagedList { _ throws(ApiError) in Page(items: [], nextCursor: nil, total: 0) }
        wardrobe = makeWardrobe(query)
        reviews = PagedList { [weak self, api, origin] cursor throws(ApiError) in
            try await api.reviews(username: self?.username ?? username, cursor: cursor, automatic: origin.isAutomatic)
        }
    }

    var actions: MemberProfileActions? { profile.map(MemberProfileActions.init) }

    func isRunning(_ work: Work) -> Bool { running.contains(work) }

    /// "Voir les # résultats" and the tab title: the items the current category holds.
    var wardrobeCount: Int {
        guard let profile else { return wardrobe.total ?? 0 }
        return WardrobeFilterRules.count(for: wardrobeQuery.category, total: profile.wardrobeTotal,
                                         categories: profile.wardrobeCategories)
    }

    // MARK: Loading

    /// The first load: the profile and the wardrobe together.
    func loadIfNeeded() async {
        guard profile == nil, loadError == nil, reloadTask == nil else { return }
        async let list: Void = wardrobe.loadIfNeeded()
        await reload()
        await list
    }

    /// "Retry" after a failed first load.
    func retry() async {
        loadError = nil
        async let list: Void = wardrobe.loadIfNeeded()
        await reload()
        await list
    }

    /// Pull-to-refresh: the profile and the list on screen.
    func refresh() async {
        async let list: Bool = tab == .wardrobe ? wardrobe.refresh() : reviews.refresh()
        await reload()
        _ = await list
    }

    /// The profile again (after an action, a sign-in). Joins a reload already running.
    func reload(automatic: Bool = false) async {
        if let reloadTask {
            await reloadTask.value
            return
        }
        let task = Task { await self.fetch(automatic: automatic) }
        reloadTask = task
        await task.value
        reloadTask = nil
    }

    private func fetch(automatic: Bool) async {
        let member = memberId
        do {
            #if DEBUG
            try origin.debugFailFirstLoad()
            #endif
            let fresh = try await api.member(username: username, automatic: automatic)
            let renamed = fresh.username != username
            username = fresh.username
            profile = fresh
            loadError = nil
            refreshError = nil
            loadedFor = .some(member)
            // A link's category the member does not sell in: the whole wardrobe instead.
            let sanitized = WardrobeFilterRules.sanitized(wardrobeQuery, categories: fresh.wardrobeCategories)
            if sanitized != wardrobeQuery {
                applyWardrobe(sanitized)
            } else if renamed, wardrobe.error != nil {
                // The former username's list failed: try again under the current one.
                await wardrobe.reload()
            }
        } catch {
            if error.isNotFound {
                // Suspended, or no such member: "no longer available", even over a profile on screen.
                profile = nil
                loadError = error
            } else if profile == nil {
                loadError = error
            } else if !automatic {
                refreshError = error
            }
        }
    }

    /// Another member signed in or out: the flags (follow, block, own profile) and hearts are theirs now.
    func memberDidChange(to memberId: String?) async {
        guard memberId != self.memberId else { return }
        self.memberId = memberId
        guard profile != nil || loadError != nil else { return }
        wardrobe = makeWardrobe(wardrobeQuery)
        async let list: Void = wardrobe.loadIfNeeded()
        await reload()
        await list
    }

    /// Signed in from a button: the profile again for this member, then the action if it is still offered.
    func resolvePending(_ action: PendingAction, memberId: String?) async -> PendingAction? {
        if memberId != self.memberId {
            await memberDidChange(to: memberId)
        } else if loadedFor != .some(memberId) || reloadTask != nil {
            await reload()
        }
        guard let actions else { return nil }
        let allowed = switch action {
        // Following already (or blocked, or their own profile): nothing left to do.
        case .follow: actions.primary == .follow(following: false)
        case .block: actions.showsBlockMenu && !actions.showsBlockedNotice
        case .report: actions.showsReport
        case .shopBundle: actions.showsShopBundle
        }
        return allowed ? action : nil
    }

    func wentToBackground(at instant: ContinuousClock.Instant = .now) {
        backgroundSince = instant
    }

    /// Back after a while (screens.md §0.6): the profile and the list on screen again, quietly.
    func returnedToForeground(at instant: ContinuousClock.Instant = .now) async {
        guard let since = backgroundSince else { return }
        backgroundSince = nil
        guard instant - since >= Self.foregroundReloadAfter, profile != nil else { return }
        origin.isAutomatic = true
        defer { origin.isAutomatic = false }
        let list = tab == .wardrobe ? wardrobe : nil
        async let refreshed: Bool = list?.hasLoaded == true ? list?.refresh() ?? false : false
        await reload(automatic: true)
        _ = await refreshed
    }

    // MARK: Wardrobe filter

    /// "Voir les # résultats": the wardrobe with this category and sort, from its first page.
    func applyWardrobe(_ query: WardrobeQuery) {
        guard query != wardrobeQuery || wardrobe.error != nil else { return }
        wardrobeQuery = query
        wardrobe = makeWardrobe(query)
    }

    private func makeWardrobe(_ query: WardrobeQuery) -> PagedList<ListingSummary> {
        PagedList { [weak self, api, origin, username] cursor throws(ApiError) in
            try await api.wardrobe(username: self?.username ?? username, query: query, cursor: cursor,
                                   automatic: origin.isAutomatic)
        }
    }

    // MARK: Actions

    /// "Suivre" / "Suivi": no confirmation (screens.md §7 G5). The count comes from the answer.
    func toggleFollow() async -> Outcome {
        guard let profile, case let .follow(following) = MemberProfileActions(profile: profile).primary,
              begin(.follow) else { return .done }
        defer { end(.follow) }
        do {
            let result = try await api.setFollowing(username: username, following: !following)
            self.profile?.isFollowing = result.isFollowing
            self.profile?.followersCount = result.followersCount
            return .done
        } catch {
            return await failure(error)
        }
    }

    /// Block after the confirmation, then the profile again so that its flags apply (slice C).
    func block() async -> Outcome {
        await setBlocked(true)
    }

    /// "Débloquer": no confirmation. The follows that ended do not come back.
    func unblock() async -> Outcome {
        await setBlocked(false)
    }

    private func setBlocked(_ blocked: Bool) async -> Outcome {
        guard let profile, !profile.isMe, begin(.block) else { return .done }
        defer { end(.block) }
        do {
            try await api.setBlocked(username: username, blocked: blocked)
            await reload()
            return blocked ? .blocked(profile.displayName) : .unblocked(profile.displayName)
        } catch {
            return await failure(error)
        }
    }

    // MARK: Errors

    /// Reloads when the error says the profile or the relation changed (slices B and C), then hands the
    /// error to the screen.
    private func failure(_ error: ApiError) async -> Outcome {
        switch error.code {
        case .notFound, .blocked, .forbidden:
            await reload()
        default:
            break
        }
        return .failed(error)
    }

    private func begin(_ work: Work) -> Bool {
        guard !running.contains(work) else { return false }
        running.insert(work)
        return true
    }

    private func end(_ work: Work) {
        running.remove(work)
    }
}

/// Whether the requests running now were asked for by the member, shared with the lists' closures.
@MainActor
private final class MemberRequestOrigin {
    var isAutomatic = false

    #if DEBUG
    private var debugFailed = false

    /// `-TaleedDebugMember offline` fails the first load (screenshots of the offline state).
    func debugFailFirstLoad() throws(ApiError) {
        guard UserDefaults.standard.string(forKey: "TaleedDebugMember") == "offline", !debugFailed else { return }
        debugFailed = true
        throw .network
    }
    #endif
}
