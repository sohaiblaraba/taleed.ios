import Foundation
@testable import Taleed
import Testing

// Fixtures and fakes of the offers and bundles tests (G10).

// MARK: - Fixtures

func fixtureOffer(id: String = "o1", amount: Int = 4000, status: ChatOfferStatus = .pending,
                  expiresIn seconds: TimeInterval = 3600, isMine: Bool = false, sentBy: ChatRole = .buyer,
                  bundle: ChatBundle? = nil, canAccept: Bool = false, canDecline: Bool = false, canCounter: Bool = false,
                  canCancel: Bool = false, canPay: Bool = false, counterRange: AmountRange? = nil) -> ChatOffer {
    ChatOffer(id: id, amount: amount, status: status, expiresAt: chatNow.addingTimeInterval(seconds), createdAt: chatNow,
              senderId: isMine ? "me" : "other", isMine: isMine, sentBy: sentBy, listingId: "l1", bundle: bundle,
              canAccept: canAccept, canDecline: canDecline, canCounter: canCounter, canCancel: canCancel, canPay: canPay,
              counterRange: counterRange)
}

func fixtureConversation(role: ChatRole = .buyer, canReply: Bool = true, isOfficial: Bool = false,
                         offerRange: AmountRange? = AmountRange(min: 1650, max: 5500),
                         pendingOffer: ChatOffer? = nil, payableOffer: ChatOffer? = nil) -> ConversationDetail {
    ConversationDetail(id: "c1", role: role, counterpart: .fixture(), listing: .fixture(), isOfficial: isOfficial, unreadCount: 0,
                       canReply: canReply, replyBlock: nil, isBlocked: false, offerRange: offerRange, pendingOffer: pendingOffer,
                       payableOffer: payableOffer)
}

func fixtureOfferMessage(_ id: String, offer: ChatOffer, at seconds: TimeInterval = 0) -> ChatMessage {
    .fixture(id, kind: .offer, isMine: offer.isMine, at: seconds, text: nil, offer: offer)
}

func fixtureLine(_ id: String, available: Bool = true) -> BundleLine {
    BundleLine(listingId: id, title: "Article \(id)", price: 2000, imageURL: nil, isAvailable: available)
}

func fixtureBundle(id: String = "b1", status: BundleDetail.Status = .open, items: [BundleLine] = [fixtureLine("a"), fixtureLine("b")],
                   acceptedOffer: AcceptedOfferRef? = nil, canBuy: Bool = true,
                   offerRange: AmountRange? = AmountRange(min: 1200, max: 4000), orderId: String? = nil) -> BundleDetail {
    BundleDetail(id: id, status: status, seller: .fixture(username: "amina"), items: items,
                 unavailableCount: items.filter { !$0.isAvailable }.count, subtotal: 4000, acceptedOffer: acceptedOffer,
                 itemsTotal: acceptedOffer?.amount ?? 4000, protectionFee: 250, shippingFrom: 400, total: 4650,
                 offerRange: offerRange, canBuy: canBuy, orderId: orderId)
}

func fixtureProfile(openBundleId: String?, canBundle: Bool = true) -> Taleed.MemberProfile {
    let base = Taleed.MemberProfile.fixture(canBundle: canBundle)
    return Taleed.MemberProfile(
        id: base.id, username: base.username, displayName: base.displayName, avatarURL: nil, isVerified: false, isOfficial: false,
        bio: nil, wilaya: nil, memberSince: base.memberSince, lastSeenAt: nil, isOnline: false, rating: nil, salesCount: 0,
        followersCount: 0, followingCount: 0, checks: base.checks, isMe: false, isFollowing: false, isBlocked: false,
        canBundle: canBundle, openBundleId: openBundleId, wardrobeTotal: 3, wardrobeCategories: [], shareURL: nil
    )
}

// MARK: - Fakes

@MainActor
final class FakeOffersApi: OffersApi {
    var result: Result<OfferActionResult, Taleed.ApiError>
    private(set) var made: [Int] = []
    private(set) var responses: [(OfferResponse, String)] = []
    private(set) var counters: [(String, Int)] = []

    init(result: Result<OfferActionResult, Taleed.ApiError>) {
        self.result = result
    }

    func makeConversationOffer(conversationId: String, amount: Int) async throws(Taleed.ApiError) -> OfferActionResult {
        made.append(amount)
        return try result.get()
    }

    func respond(_ response: OfferResponse, offerId: String) async throws(Taleed.ApiError) -> OfferActionResult {
        responses.append((response, offerId))
        return try result.get()
    }

    func counter(offerId: String, amount: Int) async throws(Taleed.ApiError) -> OfferActionResult {
        counters.append((offerId, amount))
        return try result.get()
    }
}

@MainActor
final class FakeBundlesApi: BundlesApi {
    var review: Result<BundleDetail, Taleed.ApiError> = .success(fixtureBundle())
    var saveResult: Result<BundleDetail, Taleed.ApiError>?
    var offerResult: Result<OfferActionResult, Taleed.ApiError> =
        .success(OfferActionResult(conversationId: "c9", offer: fixtureOffer(), messages: []))
    var askResult: Result<String, Taleed.ApiError> = .success("c9")
    private(set) var saved: [[String]] = []
    private(set) var reviewCalls = 0

    func bundleReview(id: String, automatic: Bool) async throws(Taleed.ApiError) -> BundleDetail {
        reviewCalls += 1
        return try review.get()
    }

    func saveBundleSelection(sellerUsername: String, listingIds: [String]) async throws(Taleed.ApiError) -> BundleDetail {
        saved.append(listingIds)
        if let saveResult { return try saveResult.get() }
        return fixtureBundle(items: listingIds.map { fixtureLine($0) })
    }

    func makeBundleOffer(bundleId: String, amount: Int) async throws(Taleed.ApiError) -> OfferActionResult {
        try offerResult.get()
    }

    func askAboutBundle(bundleId: String) async throws(Taleed.ApiError) -> String {
        try askResult.get()
    }
}

func apiFailure(_ code: ApiErrorCode, status: Int = 409) -> Taleed.ApiError {
    .failed(ApiFailure(status: status, code: code))
}
