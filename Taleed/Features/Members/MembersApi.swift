import Foundation
import TaleedAPI

/// The calls of the member profile (screens.md §2 G5): the profile, its wardrobe and reviews, follow
/// and block. Reporting the member goes through `ReportsApi` (`memberId` = the profile's `id`).
@MainActor
protocol MembersApi: AnyObject {
    /// `GET /members/{username}`. A former username answers the member under the current one.
    /// `automatic`: a reload the member did not ask for (return to the foreground).
    func member(username: String, automatic: Bool) async throws(ApiError) -> MemberProfile
    /// `GET /members/{username}/listings`: 24 cards a page, reserved and sold items included.
    func wardrobe(username: String, query: WardrobeQuery, cursor: String?, automatic: Bool) async throws(ApiError)
        -> Page<ListingSummary>
    /// `GET /members/{username}/reviews`: newest first, 20 a page.
    func reviews(username: String, cursor: String?, automatic: Bool) async throws(ApiError) -> Page<MemberReview>
    /// `PUT` (`following`) or `DELETE /members/{username}/follow`. Both are idempotent.
    func setFollowing(username: String, following: Bool) async throws(ApiError) -> FollowResult
    /// `PUT` (`blocked`) or `DELETE /members/{username}/block`. Both are idempotent.
    func setBlocked(username: String, blocked: Bool) async throws(ApiError)
}

/// The answer of `PUT` / `DELETE /members/{username}/follow`.
struct FollowResult: Equatable, Sendable {
    let isFollowing: Bool
    let followersCount: Int
}

extension GeneratedTaleedApi: MembersApi {
    func member(username: String, automatic: Bool) async throws(ApiError) -> MemberProfile {
        let profile = try await caller.call(.read, automatic: automatic) {
            try await MembersAPI.getMember(username: username, apiConfiguration: $0)
        }
        return MemberProfile(profile)
    }

    func wardrobe(username: String, query: WardrobeQuery, cursor: String?, automatic: Bool) async throws(ApiError)
        -> Page<ListingSummary> {
        let asOf = ContinuousClock.now
        let sort = MemberListingSort(rawValue: query.sort.rawValue)
        // A slug or id the API would reject (over 100 characters) names no category: left out.
        let category = query.category.flatMap { $0.utf16.count <= ListingSearchParameters.maxSlugLength ? $0 : nil }
        let page = try await caller.call(.read, automatic: automatic) {
            try await MembersAPI.listMemberListings(username: username, category: category, sort: sort, cursor: cursor,
                                                    apiConfiguration: $0)
        }
        return Page(items: page.items.map { ListingSummary($0, asOf: asOf) }, nextCursor: page.nextCursor, total: page.total)
    }

    func reviews(username: String, cursor: String?, automatic: Bool) async throws(ApiError) -> Page<MemberReview> {
        let page = try await caller.call(.read, automatic: automatic) {
            try await MembersAPI.listMemberReviews(username: username, cursor: cursor, apiConfiguration: $0)
        }
        return Page(items: page.items.map(MemberReview.init), nextCursor: page.nextCursor, total: page.total)
    }

    func setFollowing(username: String, following: Bool) async throws(ApiError) -> FollowResult {
        // A member's action: never repeated on its own (screens.md §0.6), although it is idempotent.
        let state = try await caller.call(.write) {
            following
                ? try await MembersAPI.followMember(username: username, apiConfiguration: $0)
                : try await MembersAPI.unfollowMember(username: username, apiConfiguration: $0)
        }
        return FollowResult(isFollowing: state.isFollowing, followersCount: state.followersCount)
    }

    func setBlocked(username: String, blocked: Bool) async throws(ApiError) {
        try await caller.call(.write) {
            blocked
                ? try await SafetyAPI.blockMember(username: username, apiConfiguration: $0)
                : try await SafetyAPI.unblockMember(username: username, apiConfiguration: $0)
        }
    }
}

// MARK: - Mapping

extension MemberProfile {
    init(_ profile: TaleedAPI.MemberProfile) {
        self.init(
            id: profile.id,
            username: profile.username,
            displayName: profile.displayName,
            avatarURL: profile.avatarUrl.flatMap(URL.init(string:)),
            isVerified: profile.isVerified,
            isOfficial: profile.isOfficial,
            bio: profile.bio.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 },
            wilaya: profile.wilaya.map { CatalogWilaya(id: $0.id, name: $0.name) },
            memberSince: profile.memberSince,
            lastSeenAt: profile.lastSeenAt,
            isOnline: profile.isOnline,
            rating: profile.rating.flatMap { $0.count >= 1 ? MemberRating(average: $0.average, count: $0.count) : nil },
            salesCount: profile.salesCount,
            followersCount: profile.followersCount,
            followingCount: profile.followingCount,
            checks: MemberChecks(email: profile.checks.email, phone: profile.checks.phone, identity: profile.checks.identity),
            isMe: profile.isMe,
            isFollowing: profile.isFollowing,
            isBlocked: profile.isBlocked,
            canBundle: profile.canBundle,
            openBundleId: profile.openBundleId,
            wardrobeTotal: profile.wardrobe.total,
            wardrobeCategories: profile.wardrobe.categories.map {
                WardrobeCategory(id: $0.id, slug: $0.slug, name: $0.name, parentName: $0.parent?.name, count: $0.count)
            },
            shareURL: URL(string: profile.shareUrl)
        )
    }
}

private extension MemberReview {
    init(_ review: TaleedAPI.Review) {
        self.init(
            id: review.id,
            // Outside 1–5 would draw no sensible stars: kept within the range.
            rating: min(5, max(1, review.rating)),
            comment: review.comment.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 },
            createdAt: review.createdAt,
            author: MemberRef(review.author)
        )
    }
}

extension MemberRef {
    init(_ member: MemberSummary) {
        self.init(
            id: member.id,
            username: member.username,
            displayName: member.displayName,
            avatarURL: member.avatarUrl.flatMap(URL.init(string:)),
            isVerified: member.isVerified,
            isOfficial: member.isOfficial
        )
    }
}
