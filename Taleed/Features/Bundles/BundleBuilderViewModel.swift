import Foundation
import Observation

/// The rules of the bundle builder (screens.md §2 G10 screen 4, §7 G10). Pure, so the tests check them.
enum BundleBuilderRules {
    /// A bundle holds 20 items at most (`MAX_BUNDLE_ITEMS`; the API keeps the first 20).
    static let maxItems = 20

    /// The builder opens when the server allows a bundle with this member (`canBundle`: never the
    /// member's own wardrobe, never across a block, at least two items for sale).
    static func canBuild(_ profile: MemberProfile) -> Bool {
        profile.canBundle && !profile.isMe && !profile.isBlocked
    }

    /// "Ajouter" is offered for an item for sale while the bundle has room; "Retirer" always.
    static func canAdd(_ listing: ListingSummary, selection: [String]) -> Bool {
        listing.status == .active && selection.count < maxItems && !selection.contains(listing.id)
    }

    /// The selection on screen after the bundle changed on another screen (the listing's "Ajouter au lot",
    /// a removal on the review screen): those changes apply to it, the member's picks not saved yet stay.
    /// - Parameters:
    ///   - local: the selection on screen, in the order the member picked.
    ///   - previous: the bundle's items when the builder last read or saved it.
    ///   - server: the bundle's items now.
    static func merge(local: [String], previous: [String], server: [String]) -> [String] {
        let removed = Set(previous).subtracting(server)
        var merged = local.filter { !removed.contains($0) }
        for id in server where !merged.contains(id) {
            merged.append(id)
        }
        return Array(merged.prefix(maxItems))
    }
}

/// The bundle builder (screens.md §2 G10 screen 4, website `member/bundle-shop.tsx`): the seller's
/// wardrobe with "Ajouter" / "Retirer" under each item, preselected from the member's open bundle
/// (`openBundleId`, `GET /bundles/{id}`). The selection stays in memory (§7 G10) until "Voir le lot"
/// saves it (`PUT /members/{username}/bundle`), which answers the server's totals.
@MainActor
@Observable
final class BundleBuilderViewModel {
    let username: String
    let wardrobe: PagedList<ListingSummary>
    private(set) var profile: MemberProfile?
    /// The profile failed to load (a `404`: "no longer available").
    private(set) var loadError: ApiError?
    /// The ids picked, in the order the member picked them.
    private(set) var selection: [String] = []
    private(set) var isSaving = false
    /// A toast to show (the screen clears it).
    var notice: ApiError?

    @ObservationIgnored private let members: MembersApi
    @ObservationIgnored private let bundles: BundlesApi
    /// The bundle's items when the builder last read or saved it.
    @ObservationIgnored private var serverSelection: [String] = []

    init(username: String, members: MembersApi, bundles: BundlesApi) {
        self.username = username
        self.members = members
        self.bundles = bundles
        wardrobe = PagedList { [members] cursor throws(ApiError) in
            try await members.wardrobe(username: username, query: WardrobeQuery(), cursor: cursor, automatic: false)
        }
    }

    var isLoading: Bool { profile == nil && loadError == nil }
    var canBuild: Bool { profile.map(BundleBuilderRules.canBuild) ?? false }
    var isFull: Bool { selection.count >= BundleBuilderRules.maxItems }

    func isSelected(_ listingId: String) -> Bool { selection.contains(listingId) }

    func canAdd(_ listing: ListingSummary) -> Bool {
        BundleBuilderRules.canAdd(listing, selection: selection)
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard profile == nil, loadError == nil else { return }
        await load()
    }

    /// The profile (`canBundle`, `openBundleId`), then the open bundle's items to preselect.
    func load() async {
        loadError = nil
        do {
            let profile = try await members.member(username: username, automatic: false)
            self.profile = profile
            guard BundleBuilderRules.canBuild(profile) else { return }
            let saved = try await openBundleItems(of: profile)
            selection = saved
            serverSelection = saved
        } catch {
            guard !Task.isCancelled else { return }
            if profile == nil || error.isNotFound {
                profile = nil
                loadError = error
            } else {
                notice = error
            }
        }
    }

    /// Back on the builder from another screen: the bundle may have changed there (the listing's
    /// toggle, the review screen); its changes apply to the selection on screen.
    func resync() async {
        guard let current = profile, BundleBuilderRules.canBuild(current) else { return }
        do {
            let fresh = try await members.member(username: username, automatic: true)
            profile = fresh
            let server = try await openBundleItems(of: fresh)
            selection = BundleBuilderRules.merge(local: selection, previous: serverSelection, server: server)
            serverSelection = server
        } catch {
            // Quiet: the selection on screen stays; "Voir le lot" saves it anyway.
        }
    }

    private func openBundleItems(of profile: MemberProfile) async throws(ApiError) -> [String] {
        guard let bundleId = profile.openBundleId else { return [] }
        let bundle = try await bundles.bundleReview(id: bundleId, automatic: false)
        guard bundle.status == .open else { return [] }
        return bundle.availableItems.map(\.listingId)
    }

    // MARK: Selection

    /// "Ajouter" or "Retirer".
    func toggle(_ listing: ListingSummary) {
        if let index = selection.firstIndex(of: listing.id) {
            selection.remove(at: index)
        } else if canAdd(listing) {
            selection.append(listing.id)
        }
    }

    /// "Voir le lot (N articles)": saves the selection and answers the bundle to review.
    func review() async -> String? {
        guard !selection.isEmpty, !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await bundles.saveBundleSelection(sellerUsername: profile?.username ?? username, listingIds: selection)
            // Items no longer for sale were left out: the bundle is what the server kept.
            selection = saved.listingIds
            serverSelection = saved.listingIds
            return saved.id
        } catch {
            notice = error
            if error.code == .blocked || error.code == .forbidden || error.isNotFound { await load() }
            return nil
        }
    }
}
