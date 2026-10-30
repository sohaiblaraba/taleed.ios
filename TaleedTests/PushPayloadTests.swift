import Foundation
@testable import Taleed
import Testing
import UserNotifications

struct PushPayloadTests {
    /// Every `data.url` that `POST /dev/notifications/test` produces (`src/lib/notification-samples.ts`), on the
    /// local backend's host as pushes carry it in Debug, and the screen a tap opens.
    @Test(arguments: [
        // MESSAGE, NEW_OFFER, OFFER_ACCEPTED_SELLER, OFFER_DECLINED, OFFER_COUNTERED (and their fallback).
        ("/inbox/cmconv1", AppDestination.screen(.conversation(id: "cmconv1"))),
        ("/inbox", .inbox),
        // NEW_FAVORITE: the conversation with the member who hearted it, found or created.
        ("/listings/cmlisting1/chat?with=cmmember1", .listingChat(listingId: "cmlisting1", memberId: "cmmember1")),
        // NEW_FAVORITE and BOOST_* fallback, ORDER_CANCELLED_BY_BUYER, BOOST_*, FOLLOWED_MEMBER_LISTED.
        ("/listings/cmlisting1", .screen(.listing(id: "cmlisting1"))),
        ("/sell", .sell),
        // OFFER_ACCEPTED: the bundle, or the checkout with the offer.
        ("/bundle/cmbundle1", .screen(.bundle(id: "cmbundle1"))),
        ("/checkout/cmlisting1?offer=cmoffer1",
         .screen(.checkout(CheckoutTarget(listingId: "cmlisting1", offerId: "cmoffer1", bundleId: nil)))),
        // ORDER_*, DISPUTE_* (the order of the dispute), REVIEW_RECEIVED, REFUND_SENT, and their fallback.
        ("/orders/cmorder1", .screen(.order(id: "cmorder1"))),
        ("/orders", .screen(.orders)),
        // ORDER_COMPLETED, PAYOUT_*, TOPUP_PAID, REFERRAL_REWARD, VERIFICATION_VOUCHER.
        ("/wallet", .screen(.wallet)),
        // NEW_FOLLOWER, and its fallback; REPORT_RESOLVED, REPORT_DISMISSED.
        ("/members/amina", .screen(.member(username: "amina"))),
        ("/notifications", .screen(.notifications)),
        // VERIFICATION_APPROVED, VERIFICATION_REJECTED.
        ("/settings", .screen(.settings)),
        // REFERRAL_SIGNUP.
        ("/referrals", .screen(.referrals)),
        // FOLLOWED_MEMBER_LISTED fallback.
        ("/browse", .explore(ExploreQuery())),
        // ROLE_REVOKED, and ROLE_OFFERED (staff tooling stays on the website, screens.md Q9): Home.
        ("/", .home),
        ("/role-offers", .home),
        // Team types: admin pages are not in the apps.
        ("/admin/payouts", .home),
    ])
    func eachTestNotificationLinkOpensItsScreen(path: String, destination: AppDestination) {
        let push = PushPayload(userInfo: ["type": "ANY", "url": "http://localhost:3000\(path)"])
        #expect(push.destination == destination)
        // The production host and a language prefix open the same screen.
        #expect(PushPayload(url: "https://taleed.app/ar\(path)").destination == destination)
    }

    /// The payload as Firebase delivers it: the `data` fields next to `aps`.
    @Test func readsTheDataFieldsOfTheAPNsPayload() {
        let push = PushPayload(userInfo: [
            "aps": ["alert": ["title": "@amina", "body": "Je l'envoie demain."], "thread-id": "conv-cm1"],
            "type": "MESSAGE",
            "url": "https://taleed.app/inbox/cm1",
            "conversationId": "cm1",
            "gcm.message_id": "1",
        ])
        #expect(push.isMessage)
        #expect(push.conversation == "cm1")
        #expect(push.destination == .screen(.conversation(id: "cm1")))
    }

    /// No `url`: the conversation of `conversationId`, otherwise Home.
    @Test func withoutALinkOpensTheConversationOrHome() {
        #expect(PushPayload(type: "MESSAGE", conversationId: "cm2").destination == .screen(.conversation(id: "cm2")))
        #expect(PushPayload(userInfo: ["type": "ORDER_SHIPPED", "url": "  "]).destination == .home)
    }

    /// In the foreground: nothing for the conversation on screen, a banner for the rest.
    @Test func theConversationOnScreenShowsNoBanner() {
        let message = PushPayload(type: "MESSAGE", url: "https://taleed.app/inbox/cm1", conversationId: "cm1")
        #expect(message.foregroundPresentation(conversationOnScreen: "cm1") == [])
        #expect(message.foregroundPresentation(conversationOnScreen: "cm9") == [.banner, .list, .sound])
        #expect(message.foregroundPresentation(conversationOnScreen: nil) == [.banner, .list, .sound])
        // A conversation's link without `conversationId` counts too.
        #expect(PushPayload(type: "NEW_OFFER", url: "/inbox/cm1").foregroundPresentation(conversationOnScreen: "cm1") == [])
        let order = PushPayload(type: "ORDER_SHIPPED", url: "https://taleed.app/orders/cm3")
        #expect(order.foregroundPresentation(conversationOnScreen: "cm1") == [.banner, .list, .sound])
    }

    /// A tap that comes before the app's objects exist (app killed) waits for them, then opens once.
    @MainActor
    @Test func aTapBeforeTheAppIsReadyWaits() {
        let center = PushNotificationCenter()
        center.didOpen(PushPayload(url: "/orders/cm4"))
        var opened: [AppDestination] = []
        center.onOpen = { opened.append($0.destination) }
        #expect(opened == [.screen(.order(id: "cm4"))])
        center.didOpen(PushPayload(url: "/wallet"))
        #expect(opened == [.screen(.order(id: "cm4")), .screen(.wallet)])
    }

    /// A message push in the foreground bumps the inbox's reload and reaches `onArrival`.
    @MainActor
    @Test func anArrivalReloadsTheLists() {
        let center = PushNotificationCenter()
        var arrivals: [String?] = []
        center.onArrival = { arrivals.append($0.type) }
        center.conversationOnScreen = { "cm1" }
        #expect(center.willPresent(PushPayload(type: "MESSAGE", conversationId: "cm1")) == [])
        #expect(center.willPresent(PushPayload(type: "ORDER_PAID", url: "/orders/cm5")) == [.banner, .list, .sound])
        #expect(center.messageArrivals == 1)
        #expect(arrivals == ["MESSAGE", "ORDER_PAID"])
    }
}
