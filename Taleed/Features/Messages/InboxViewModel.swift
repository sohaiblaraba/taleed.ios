import Foundation
import Observation

/// The inbox's optional filter by the member's side, done on the device (screens.md §2 G9).
enum InboxFilter: Int, CaseIterable, Sendable {
    case all, buying, selling

    /// Announcements are neither purchases nor sales: they show under "Tous" only.
    func includes(_ conversation: InboxConversation) -> Bool {
        switch self {
        case .all: true
        case .buying: !conversation.isOfficial && conversation.role == .buyer
        case .selling: !conversation.isOfficial && conversation.role == .seller
        }
    }
}

/// The Messages tab's list (`GET /conversations`, slice C "Inbox"): most recent activity first, 30 a
/// page, de-duplicated by id. Reloads from the top on pull, on return to the foreground and when the
/// member comes back to it from a conversation (a conversation with news moves to the top).
@MainActor
@Observable
final class InboxViewModel {
    let list: PagedList<InboxConversation>
    var filter: InboxFilter = .all

    @ObservationIgnored private let pager: InboxPager
    /// The last read mark applied, so that an old one never clears a row that has news again.
    @ObservationIgnored private var appliedReadSequence = 0
    /// Back on screen sooner than this after a load: the list is fresh enough.
    static let quietReloadInterval: Duration = .seconds(2)

    init(api: MessagesApi) {
        let pager = InboxPager(api: api)
        self.pager = pager
        list = PagedList { cursor throws(ApiError) in try await pager.fetch(cursor: cursor) }
    }

    /// The conversations the filter keeps, in the inbox's order.
    var visibleItems: [InboxConversation] {
        list.items.filter(filter.includes)
    }

    /// Nothing at all in the inbox (not just under the filter).
    var isEmpty: Bool { list.isEmpty }

    /// Back on the inbox (return to the foreground, back from a conversation, the tab selected again):
    /// the first page again, quietly, keeping the rows on screen.
    func reloadQuietly(now: ContinuousClock.Instant = .now) async {
        guard list.hasLoaded, !list.isRefreshing, !list.isLoadingFirstPage else { return }
        if let lastLoad = pager.lastFirstPage, now - lastLoad < Self.quietReloadInterval { return }
        pager.isAutomatic = true
        defer { pager.isAutomatic = false }
        await list.refresh()
    }

    /// A read the conversation screen reported (`ConversationReads`), applied once.
    func apply(_ mark: ConversationReads.Mark) {
        guard mark.sequence > appliedReadSequence else { return }
        appliedReadSequence = mark.sequence
        markRead(conversationId: mark.conversationId)
    }

    /// The member read a conversation: its row loses its counter at once.
    func markRead(conversationId: String) {
        guard var row = list.items.first(where: { $0.id == conversationId }), row.unreadCount > 0 else { return }
        row.unreadCount = 0
        list.update(row)
    }
}

/// Fetches the inbox's pages for `PagedList`.
@MainActor
final class InboxPager {
    /// Marks the requests of a quiet reload, which pause while the API asks to wait (`429`).
    var isAutomatic = false
    /// When the last first page was asked for.
    private(set) var lastFirstPage: ContinuousClock.Instant?

    private let api: MessagesApi

    init(api: MessagesApi) {
        self.api = api
    }

    func fetch(cursor: String?) async throws(ApiError) -> Page<InboxConversation> {
        if cursor == nil { lastFirstPage = .now }
        #if DEBUG
        if let page = try debugAnswer() { return page }
        #endif
        return try await api.conversations(cursor: cursor, automatic: isAutomatic)
    }

    #if DEBUG
    private var failedOnce = false

    /// `-TaleedDebugInbox offline` fails the first request (then works); `empty` answers an empty inbox.
    private func debugAnswer() throws(ApiError) -> Page<InboxConversation>? {
        switch UserDefaults.standard.string(forKey: "TaleedDebugInbox") {
        case "offline" where !failedOnce:
            failedOnce = true
            throw .network
        case "empty":
            return Page(items: [], nextCursor: nil, total: 0)
        default:
            return nil
        }
    }
    #endif
}
