import Foundation
@testable import Taleed
import Testing

// MARK: - Pinned offer and the offer entry

struct PinnedOfferTests {
    private let identity: (ChatOffer) -> ChatOffer = { $0 }

    @Test func theOfferWaitingIsPinnedWithItsFlaggedButtons() throws {
        let pending = fixtureOffer(canAccept: true, canDecline: true, canCounter: true, counterRange: AmountRange(min: 1650, max: 5500))
        let pinned = try #require(PinnedOffer.find(conversation: fixtureConversation(pendingOffer: pending),
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
        #expect(PinnedOffer.find(conversation: fixtureConversation(pendingOffer: lapsed), current: identity,
                                 now: chatNow) == nil)
        #expect(!PinnedOffer(offer: lapsed, now: chatNow).hasActions)
    }

    @Test func theOfferTheBuyerCanPayIsPinnedWithItsCheckout() throws {
        let accepted = fixtureOffer(id: "o2", status: .accepted, canPay: true)
        let pinned = try #require(PinnedOffer.find(conversation: fixtureConversation(payableOffer: accepted), current: identity,
                                                   now: chatNow))
        #expect(pinned.payment == CheckoutTarget(listingId: "l1", offerId: "o2", bundleId: nil))
    }

    @Test func aPayableOfferPaidSinceIsNoLongerPinned() {
        let accepted = fixtureOffer(id: "o2", status: .accepted, canPay: true)
        let paid = fixtureOffer(id: "o2", status: .accepted, canPay: false)
        #expect(PinnedOffer.find(conversation: fixtureConversation(payableOffer: accepted), current: { _ in paid }, now: chatNow) == nil)
        #expect(PinnedOffer.find(conversation: fixtureConversation(), current: identity, now: chatNow) == nil)
    }

    @Test func theOfferWaitingWinsOverThePayableOne() throws {
        let pending = fixtureOffer(id: "o3", canAccept: true)
        let accepted = fixtureOffer(id: "o2", status: .accepted, canPay: true)
        let conversation = fixtureConversation(pendingOffer: pending, payableOffer: accepted)
        let pinned = try #require(PinnedOffer.find(conversation: conversation, current: identity, now: chatNow))
        #expect(pinned.offer.id == "o3")
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
        let pinned = PinnedOffer.find(conversation: fixtureConversation(pendingOffer: card), current: { _ in withdrawn },
                                      now: chatNow)
        #expect(pinned == nil)
    }

    @Test func officialThreadsPinNothing() {
        let pending = fixtureOffer(canAccept: true)
        #expect(PinnedOffer.find(conversation: fixtureConversation(isOfficial: true, pendingOffer: pending), current: identity,
                                 now: chatNow) == nil)
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

    @Test func theBuyerCounteringTheSellersPriceStartsFromAnEmptyField() {
        // The seller proposed 2 900 DA on a 3 000 DA item: the midpoint (2 950) is above the seller's price.
        let proposed = fixtureOffer(amount: 2900, sentBy: .seller, counterRange: AmountRange(min: 1200, max: 3000))
        #expect(OfferAmounts.counterSuggestion(for: proposed) == nil)
    }

    @Test func theCounterStartsHalfwayToTheTop() {
        #expect(OfferAmounts.counterSuggestion(for: fixtureOffer(amount: 4000, counterRange: AmountRange(min: 1650, max: 5500))) == 4750)
        #expect(OfferAmounts.counterSuggestion(for: fixtureOffer(amount: 4001, counterRange: AmountRange(min: 1650, max: 5500))) == 4751)
        #expect(OfferAmounts.counterSuggestion(for: fixtureOffer(amount: 100, counterRange: AmountRange(min: 900, max: 1000))) == 900)
        #expect(OfferAmounts.counterSuggestion(for: fixtureOffer(counterRange: nil)) == nil)
    }

    @Test func thePinnedCardShrinksWhileTypingAndAtAccessibilitySizes() {
        #expect(PinnedOfferLayout.of(isComposing: false, isAccessibilitySize: false, isExpanded: false) == .full)
        #expect(PinnedOfferLayout.of(isComposing: true, isAccessibilitySize: false, isExpanded: true) == .compact)
        #expect(PinnedOfferLayout.of(isComposing: false, isAccessibilitySize: true, isExpanded: false) == .compact)
        #expect(PinnedOfferLayout.of(isComposing: false, isAccessibilitySize: true, isExpanded: true) == .expanded)
    }

    @Test func theCompactCardKeepsTheMostUsefulAction() {
        let payable = PinnedOffer(offer: fixtureOffer(status: .accepted, canPay: true), now: chatNow)
        #expect(PinnedOfferMainAction(payable) == .pay(CheckoutTarget(listingId: "l1", offerId: "o1", bundleId: nil)))
        let answerable = PinnedOffer(offer: fixtureOffer(canAccept: true, canDecline: true, canCounter: true,
                                                         counterRange: AmountRange(min: 1, max: 9)), now: chatNow)
        #expect(PinnedOfferMainAction(answerable) == .accept)
        #expect(PinnedOfferMainAction(PinnedOffer(offer: fixtureOffer(isMine: true, canCancel: true), now: chatNow)) == .withdraw)
        #expect(PinnedOfferMainAction(PinnedOffer(offer: fixtureOffer(), now: chatNow)) == nil)
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

    @Test func anOfferThatLapsesRedrawsWithoutItsButtonsAndReloads() async {
        var clock = chatNow
        let pending = fixtureOffer(expiresIn: 0.05, canAccept: true, canDecline: true)
        api.conversation = .success(fixtureConversation(role: .seller, pendingOffer: pending))
        let model = ConversationViewModel(conversationId: "c1", api: api, events: events, members: members,
                                          offers: FakeOffersApi(result: .failure(.network)),
                                          upload: { _ throws(Taleed.ApiError) in UploadedPhoto(key: "k", url: nil, thumbURL: nil) },
                                          now: { clock })
        await model.load()
        #expect(model.pinnedOffer?.canAccept == true)
        #expect(model.offerEntry == nil)
        let ticks = model.clockTick
        let calls = api.conversationCalls
        // The screen waits for the deadline, which passes while it shows.
        let wait = Task { await model.followOfferExpiry() }
        // Let it start waiting before the clock moves on.
        try? await Task.sleep(for: .milliseconds(100))
        clock = chatNow.addingTimeInterval(1)
        await wait.value
        #expect(model.clockTick == ticks + 1)
        #expect(api.conversationCalls == calls + 1)
        #expect(model.pinnedOffer == nil)
        #expect(model.offerEntry == .proposePrice)
    }

    @Test func backOnTheScreenTheConversationReloadsForThePayableOffer() async {
        let accepted = fixtureOffer(id: "o2", status: .accepted, sentBy: .seller, canPay: true)
        api.conversation = .success(fixtureConversation(payableOffer: accepted))
        let model = model(FakeOffersApi(result: .failure(.network)))
        await model.load()
        await model.setVisible(true)
        #expect(model.pinnedOffer?.payment == CheckoutTarget(listingId: "l1", offerId: "o2", bundleId: nil))
        // Checkout on top, the order paid there.
        await model.setVisible(false)
        api.conversation = .success(fixtureConversation())
        await model.setVisible(true)
        #expect(model.pinnedOffer == nil)
    }
}

// MARK: - Polish P4

struct OfferAmountFieldTests {
    /// The typed amount is grouped like the bounds under it; only its digits count.
    @Test func theAmountIsGroupedAsTyped() {
        #expect(OfferAmountSheet.grouped("3500", language: .fr) == "3\u{202F}500")
        #expect(OfferAmountSheet.grouped("3\u{202F}5000", language: .fr) == "35\u{202F}000")
        #expect(OfferAmountSheet.grouped("3500", language: .ar) == "3.500")
        #expect(OfferAmountSheet.grouped("", language: .fr) == "")
        #expect(OfferAmountInput(text: "3\u{202F}500", range: AmountRange(min: 1440, max: 4800)) == .valid(3500))
    }

    @Test func thePlaceholderIsAnAmountInsideTheBounds() {
        #expect(OfferAmountSheet.example(in: AmountRange(min: 1440, max: 4800)) == 3100)
        #expect(OfferAmountSheet.example(in: AmountRange(min: 120, max: 150)) == 120)
    }
}
