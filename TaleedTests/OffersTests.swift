import Foundation
@testable import Taleed
import Testing

// MARK: - Pinned offer and the offer entry

struct PinnedOfferTests {
    private let identity: (ChatOffer) -> ChatOffer = { $0 }

    @Test func theOfferWaitingIsPinnedWithItsFlaggedButtons() throws {
        let pending = fixtureOffer(canAccept: true, canDecline: true, canCounter: true, counterRange: AmountRange(min: 1650, max: 5500))
        let pinned = try #require(PinnedOffer.find(conversation: fixtureConversation(pendingOffer: pending), messages: [],
                                                   current: identity, now: chatNow))
        #expect(pinned.offer.id == "o1")
        #expect(pinned.canAccept && pinned.canDecline && pinned.canCounter)
        #expect(!pinned.canWithdraw && pinned.payment == nil)
    }

    @Test func aCounterNeedsItsBounds() {
        let pinned = PinnedOffer(offer: fixtureOffer(canCounter: true, counterRange: nil), now: chatNow)
        #expect(!pinned.canCounter)
    }

    @Test func theMembersOwnOfferOnlyOffersWithdraw() {
        let pinned = PinnedOffer(offer: fixtureOffer(isMine: true, canCancel: true), now: chatNow)
        #expect(pinned.canWithdraw && !pinned.canAccept && !pinned.canDecline)
    }

    @Test func anExpiredOfferIsNotPinnedAndHasNoButtons() {
        let lapsed = fixtureOffer(expiresIn: -10, canAccept: true, canDecline: true, canCancel: true)
        #expect(PinnedOffer.find(conversation: fixtureConversation(pendingOffer: lapsed), messages: [], current: identity,
                                 now: chatNow) == nil)
        #expect(!PinnedOffer(offer: lapsed, now: chatNow).hasActions)
    }

    @Test func anAcceptedOfferTheBuyerCanPayIsPinnedWithItsCheckout() throws {
        let accepted = fixtureOffer(id: "o2", status: .accepted, canPay: true)
        let older = fixtureOffer(id: "o1", status: .declined)
        let messages = [fixtureOfferMessage("m2", offer: accepted, at: 20), fixtureOfferMessage("m1", offer: older)]
        let pinned = try #require(PinnedOffer.find(conversation: fixtureConversation(), messages: messages, current: identity,
                                                   now: chatNow))
        #expect(pinned.payment == CheckoutTarget(listingId: "l1", offerId: "o2", bundleId: nil))
    }

    @Test func aBundleOfferIsPaidThroughTheBundleCheckout() {
        let lot = ChatBundle(id: "b1", items: [], itemsTotal: 4000)
        let pinned = PinnedOffer(offer: fixtureOffer(status: .accepted, bundle: lot, canPay: true), now: chatNow)
        #expect(pinned.payment == CheckoutTarget(listingId: "l1", offerId: "o1", bundleId: "b1"))
    }

    @Test func theLatestStateOfAnOfferDecides() {
        // The card's copy was pending; the offer was withdrawn since.
        let card = fixtureOffer(isMine: true, canCancel: true)
        let withdrawn = fixtureOffer(status: .cancelled, isMine: true)
        let pinned = PinnedOffer.find(conversation: fixtureConversation(pendingOffer: card), messages: [], current: { _ in withdrawn },
                                      now: chatNow)
        #expect(pinned == nil)
    }

    @Test func officialThreadsPinNothing() {
        let pending = fixtureOffer(canAccept: true)
        #expect(PinnedOffer.find(conversation: fixtureConversation(isOfficial: true, pendingOffer: pending), messages: [],
                                 current: identity, now: chatNow) == nil)
    }

    @Test func theBuyerMakesAnOfferAndTheSellerProposesAPrice() {
        #expect(ConversationOfferEntry.entry(for: fixtureConversation(role: .buyer), pinned: nil, now: chatNow) == .makeOffer)
        #expect(ConversationOfferEntry.entry(for: fixtureConversation(role: .seller), pinned: nil, now: chatNow) == .proposePrice)
    }

    @Test func noOfferButtonWithoutBoundsRepliesOrWhileOneWaits() {
        #expect(ConversationOfferEntry.entry(for: fixtureConversation(offerRange: nil), pinned: nil, now: chatNow) == nil)
        #expect(ConversationOfferEntry.entry(for: fixtureConversation(canReply: false), pinned: nil, now: chatNow) == nil)
        #expect(ConversationOfferEntry.entry(for: fixtureConversation(role: .unknown), pinned: nil, now: chatNow) == nil)
        let waiting = PinnedOffer(offer: fixtureOffer(), now: chatNow)
        #expect(ConversationOfferEntry.entry(for: fixtureConversation(), pinned: waiting, now: chatNow) == nil)
        let payable = PinnedOffer(offer: fixtureOffer(status: .accepted, canPay: true), now: chatNow)
        #expect(ConversationOfferEntry.entry(for: fixtureConversation(), pinned: payable, now: chatNow) == .makeOffer)
    }

    @Test func theCounterStartsHalfwayToTheTop() {
        #expect(OfferAmounts.counterSuggestion(for: fixtureOffer(amount: 4000, counterRange: AmountRange(min: 1650, max: 5500))) == 4750)
        #expect(OfferAmounts.counterSuggestion(for: fixtureOffer(amount: 4001, counterRange: AmountRange(min: 1650, max: 5500))) == 4751)
        #expect(OfferAmounts.counterSuggestion(for: fixtureOffer(amount: 100, counterRange: AmountRange(min: 900, max: 1000))) == 900)
        #expect(OfferAmounts.counterSuggestion(for: fixtureOffer(counterRange: nil)) == nil)
    }

    @Test func offerErrorsThatReloadTheScreen() {
        for code in [ApiErrorCode.offerOutOfRange, .offerPending, .offerClosed, .listingUnavailable, .blocked,
                     .conversationReadOnly, .forbidden, .notFound] {
            #expect(apiFailure(code).reloadsOfferState)
        }
        #expect(!Taleed.ApiError.network.reloadsOfferState)
        #expect(!apiFailure(.invalidRequest, status: 400).reloadsOfferState)
    }

    @Test func theAmountFieldReadsArabicDigitsAndChecksTheBounds() {
        let range = AmountRange(min: 1650, max: 5500)
        #expect(OfferAmountInput(text: "١٠٠٠", range: range) == .outOfRange)
        #expect(OfferAmountInput(text: "4 000", range: range) == .valid(4000))
        #expect(OfferAmountInput(text: "", range: range) == .empty)
    }
}

// MARK: - Offers in the conversation

@MainActor
struct ConversationOfferActionTests {
    let api = FakeMessagesApi()
    let events = FakeEventsSource()
    let members = FakeMembersApi()

    private func model(_ offers: FakeOffersApi) -> ConversationViewModel {
        ConversationViewModel(conversationId: "c1", api: api, events: events, members: members, offers: offers,
                              upload: { _ throws(Taleed.ApiError) in UploadedPhoto(key: "k", url: nil, thumbURL: nil) },
                              now: { chatNow })
    }

    @Test func anOfferJoinsTheConversationAndReloadsIt() async {
        let made = fixtureOffer(id: "o9", isMine: true, canCancel: true)
        let offers = FakeOffersApi(result: .success(OfferActionResult(conversationId: "c1", offer: made,
                                                                      messages: [fixtureOfferMessage("m9", offer: made, at: 30)])))
        api.conversation = .success(fixtureConversation())
        let model = model(offers)
        await model.load()
        let before = api.conversationCalls
        api.conversation = .success(fixtureConversation(offerRange: nil, pendingOffer: made))
        let step = await model.makeOffer(amount: 4000)
        #expect(step == .finish)
        #expect(offers.made == [4000])
        #expect(model.messages.map(\.id).contains("m9"))
        #expect(api.conversationCalls == before + 1)
        #expect(model.notice == .confirmation(.offersOfferSent))
        #expect(model.pinnedOffer?.offer.id == "o9")
        #expect(model.offerEntry == nil)
    }

    @Test func anAmountOutOfRangeShowsTheFreshBounds() async {
        let offers = FakeOffersApi(result: .failure(apiFailure(.offerOutOfRange, status: 400)))
        api.conversation = .success(fixtureConversation())
        let model = model(offers)
        await model.load()
        api.conversation = .success(fixtureConversation(offerRange: AmountRange(min: 1500, max: 5000)))
        let step = await model.makeOffer(amount: 6000)
        #expect(step == .showRange(AmountRange(min: 1500, max: 5000)))
    }

    @Test func anOfferAlreadyWaitingClosesTheSheetWithANotice() async {
        let offers = FakeOffersApi(result: .failure(apiFailure(.offerPending)))
        api.conversation = .success(fixtureConversation())
        let model = model(offers)
        await model.load()
        #expect(await model.makeOffer(amount: 4000) == .finish)
        #expect(model.notice == .information(.offersErrorActive))
    }

    @Test func theBuyerAcceptingTheSellersPriceGoesToCheckout() async {
        let proposal = fixtureOffer(sentBy: .seller, canAccept: true, canDecline: true)
        let accepted = fixtureOffer(status: .accepted, sentBy: .seller, canPay: true)
        let offers = FakeOffersApi(result: .success(OfferActionResult(conversationId: "c1", offer: accepted, messages: [])))
        api.conversation = .success(fixtureConversation(pendingOffer: proposal))
        let model = model(offers)
        await model.load()
        let checkout = await model.respond(.accept, to: proposal)
        #expect(checkout == CheckoutTarget(listingId: "l1", offerId: "o1", bundleId: nil))
        #expect(offers.responses.map(\.0) == [.accept])
    }

    @Test func theSellerAcceptingStaysInTheConversation() async {
        let accepted = fixtureOffer(status: .accepted, canPay: false)
        let offers = FakeOffersApi(result: .success(OfferActionResult(conversationId: "c1", offer: accepted, messages: [])))
        api.conversation = .success(fixtureConversation(role: .seller, pendingOffer: fixtureOffer(canAccept: true)))
        let model = model(offers)
        await model.load()
        #expect(await model.respond(.accept, to: fixtureOffer(canAccept: true)) == nil)
    }

    @Test func aClosedOfferReloadsTheConversation() async {
        let offers = FakeOffersApi(result: .failure(apiFailure(.offerClosed)))
        api.conversation = .success(fixtureConversation(pendingOffer: fixtureOffer(canDecline: true)))
        let model = model(offers)
        await model.load()
        let before = api.conversationCalls
        #expect(await model.respond(.decline, to: fixtureOffer(canDecline: true)) == nil)
        #expect(api.conversationCalls == before + 1)
        #expect(model.notice == .error(apiFailure(.offerClosed)))
        #expect(model.offerWork == nil)
    }

    @Test func aCounterReplacesTheOffer() async {
        let counter = fixtureOffer(id: "o2", amount: 4500, isMine: true, sentBy: .seller, canCancel: true)
        let offers = FakeOffersApi(result: .success(OfferActionResult(conversationId: "c1", offer: counter, messages: [])))
        api.conversation = .success(fixtureConversation(role: .seller, pendingOffer: fixtureOffer(canCounter: true)))
        let model = model(offers)
        await model.load()
        api.conversation = .success(fixtureConversation(role: .seller, offerRange: nil, pendingOffer: counter))
        #expect(await model.counter(fixtureOffer(canCounter: true), amount: 4500) == .finish)
        #expect(offers.counters.map(\.1) == [4500])
        #expect(model.pinnedOffer?.offer.id == "o2")
        #expect(model.pinnedOffer?.canWithdraw == true)
    }
}
