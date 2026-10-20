import SwiftUI
import TaleedAPI

/// The calls of the notifications screen (screens.md §2 G15 and §7 G15, slice E "Notifications").
@MainActor
protocol NotificationsApi: AnyObject {
    /// `GET /notifications`: newest first, 30 a page; a page can hold fewer (rows the server can no
    /// longer write are left out). Marks nothing read. `automatic`: a reload the member did not ask for.
    func notifications(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<NotificationRow>
    /// `POST /notifications/read`: that notification and every older one are read; the badges after the
    /// change. Repeated freely. An `upTo` that is not one of the member's answers `404 not_found`.
    func markNotificationsRead(upTo id: String) async throws(ApiError) -> UnreadCounts
}

extension GeneratedTaleedApi: NotificationsApi {
    func notifications(cursor: String?, automatic: Bool) async throws(ApiError) -> Page<NotificationRow> {
        let page = try await caller.call(.read, automatic: automatic) {
            try await NotificationsAPI.listNotifications(cursor: cursor, apiConfiguration: $0)
        }
        return Page(items: page.items.map(NotificationRow.init), nextCursor: page.nextCursor, total: page.total)
    }

    func markNotificationsRead(upTo id: String) async throws(ApiError) -> UnreadCounts {
        // Idempotent (slice E, Retrying): the screen calls it on its own, so it pauses after a `429`.
        let counts = try await caller.call(.read, automatic: true) {
            try await NotificationsAPI.markNotificationsRead(notificationsRead: NotificationsRead(upTo: id), apiConfiguration: $0)
        }
        return UnreadCounts(messages: counts.unreadMessages, notifications: counts.unreadNotifications)
    }
}

extension NotificationRow {
    init(_ item: NotificationItem) {
        self.init(id: item.id, type: item.type, text: item.text, url: URL(apiString: item.url), isRead: item.isRead,
                  createdAt: item.createdAt)
    }
}

// MARK: Dependencies

/// What the notifications screen needs, set once at the root (`AppRootView`).
struct NotificationsDependencies {
    let api: any NotificationsApi
    /// Tells an open notifications screen that something new arrived.
    let feed: NotificationsFeed
}

private struct NotificationsDependenciesKey: EnvironmentKey {
    static var defaultValue: NotificationsDependencies? { nil }
}

extension EnvironmentValues {
    var notificationsDependencies: NotificationsDependencies? {
        get { self[NotificationsDependenciesKey.self] }
        set { self[NotificationsDependenciesKey.self] = newValue }
    }
}
