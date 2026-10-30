import Foundation
import Observation
import UserNotifications

/// What the app reads in a push (slice C, What a push carries): the `data` fields, which Firebase puts at the
/// top of the APNs payload, next to `aps`.
struct PushPayload: Equatable, Sendable {
    /// `MESSAGE`, `CAMPAIGN`, or the notification type such as `ORDER_SHIPPED`.
    let type: String?
    /// The website page of the push, such as `https://taleed.app/orders/…`.
    let url: String?
    /// Set when `url` is a conversation.
    let conversationId: String?

    static let messageType = "MESSAGE"

    init(type: String? = nil, url: String? = nil, conversationId: String? = nil) {
        self.type = type
        self.url = url
        self.conversationId = conversationId
    }

    init(userInfo: [AnyHashable: Any]) {
        func text(_ key: String) -> String? {
            guard let value = (userInfo[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        self.init(type: text("type"), url: text("url"), conversationId: text("conversationId"))
    }

    var isMessage: Bool { type == Self.messageType }

    /// Where a tap leads: the push's `url` through the link router, as a link into the app (slice C,
    /// Opening a push). A conversation push without a `url` opens its conversation; anything else, Home.
    var destination: AppDestination {
        if let url { return LinkRouter.destination(for: url) }
        if let conversationId { return .screen(.conversation(id: conversationId)) }
        return .home
    }

    /// The conversation the push is about: `conversationId`, or the one its `url` opens.
    var conversation: String? {
        if let conversationId { return conversationId }
        if case let .screen(.conversation(id, _)) = destination { return id }
        return nil
    }

    /// While the app is in the foreground (slice C): nothing for the conversation on screen, whose live
    /// stream already shows the message; a banner, the list and the sound for the rest.
    func foregroundPresentation(conversationOnScreen: String?) -> UNNotificationPresentationOptions {
        if let conversation, conversation == conversationOnScreen { return [] }
        return [.banner, .list, .sound]
    }
}

/// The notification centre's delegate: how pushes show while the app is open, and where a tap leads. It is
/// set before launch ends (`TaleedApp.init`), so the tap that launched the app (app killed) arrives too; a tap
/// that comes before the app's objects exist waits for `onOpen`.
@MainActor
@Observable
final class PushNotificationCenter: NSObject {
    static let shared = PushNotificationCenter()

    /// Bumped by each chat message push that arrives while the app is open: the inbox reloads.
    private(set) var messageArrivals = 0

    /// A tapped push: the router opens its destination (it waits for the launch flow if needed).
    @ObservationIgnored var onOpen: ((PushPayload) -> Void)? {
        didSet {
            guard let onOpen else { return }
            let waiting = pendingTaps
            pendingTaps = []
            waiting.forEach(onOpen)
        }
    }

    /// A push that arrived while the app is open (shown or not): the badges and the open lists reload.
    @ObservationIgnored var onArrival: ((PushPayload) -> Void)?

    /// The conversation on top of the selected tab, if any.
    @ObservationIgnored var conversationOnScreen: () -> String? = { nil }

    @ObservationIgnored private var pendingTaps: [PushPayload] = []

    /// Starts receiving the centre's callbacks.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// A push arrived while the app is open: what shows.
    func willPresent(_ push: PushPayload) -> UNNotificationPresentationOptions {
        if push.isMessage { messageArrivals += 1 }
        onArrival?(push)
        return push.foregroundPresentation(conversationOnScreen: conversationOnScreen())
    }

    /// The member tapped a push.
    func didOpen(_ push: PushPayload) {
        if let onOpen {
            onOpen(push)
        } else {
            pendingTaps.append(push)
        }
    }
}

// The completion-handler forms, answered on the main thread: the `async` forms finish off the main thread, and
// UIKit then aborts when a tap opens the app (`_performBlockAfterCATransactionCommitSynchronizes`).
extension PushNotificationCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let push = PushPayload(userInfo: notification.request.content.userInfo)
        nonisolated(unsafe) let completion = completionHandler
        onMain { completion($0.willPresent(push)) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let isOpen = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let push = PushPayload(userInfo: response.notification.request.content.userInfo)
        nonisolated(unsafe) let completion = completionHandler
        onMain { center in
            if isOpen { center.didOpen(push) }
            completion()
        }
    }

    /// Runs `body` on the main actor: at once when the system called on the main thread (it does), otherwise
    /// on the main queue.
    nonisolated private func onMain(_ body: @escaping @MainActor (PushNotificationCenter) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body(self) }
        } else {
            DispatchQueue.main.async { body(self) }
        }
    }
}
