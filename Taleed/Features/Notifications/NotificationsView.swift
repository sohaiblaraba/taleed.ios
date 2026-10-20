import SwiftUI

/// Notifications (screens.md §2 G15 and §7 G15; no Figma screen, built from the design system): the
/// back app bar "Notifications", then one list, newest first. Opened from the bell of the brand app bar
/// (Home, Sell), the Profile hub, a `/notifications` link or a push.
struct NotificationsView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(\.notificationsDependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.notificationsTitle), onBack: { dismiss() })
        } content: {
            if session.isSignedIn, let dependencies {
                // A new list for another member.
                NotificationsListView(dependencies: dependencies, session: session).id(session.user?.id)
            } else {
                SignInPromptView()
            }
        }
    }
}

/// The list's states: loading, the error with Retry (offline included), "Aucune notification.", the
/// rows, pull-to-refresh and the pagination footer. Reloads quietly, and marks read again, on return to
/// the foreground and when something new arrives (`NotificationsFeed`) while it is on screen.
struct NotificationsListView: View {
    @State private var model: NotificationsViewModel
    private let feed: NotificationsFeed
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.shellTab) private var shellTab
    /// Something arrived while another screen covered this one: reload once it shows again.
    @State private var reloadsWhenShown = false

    init(dependencies: NotificationsDependencies, session: SessionManager) {
        feed = dependencies.feed
        _model = State(initialValue: NotificationsViewModel(api: dependencies.api) { [weak session] counts in
            session?.updateUnreadCounts(messages: counts.messages, notifications: counts.notifications)
        })
    }

    var body: some View {
        PagedListView(list: model.list,
                      load: { await model.loadIfNeeded() },
                      refresh: { await model.refresh() },
                      retry: { await model.retry() },
                      content: { rowList($0) },
                      empty: { emptyContent })
        .accessibilityIdentifier("notifications.list")
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isOnScreen { Task { await model.reloadQuietly() } }
        }
        .onChange(of: feed.sequence) { _, _ in
            if isOnScreen {
                Task { await model.reloadQuietly() }
            } else {
                reloadsWhenShown = true
            }
        }
        .onChange(of: isOnScreen) { _, onScreen in
            guard onScreen, reloadsWhenShown else { return }
            reloadsWhenShown = false
            Task { await model.reloadQuietly() }
        }
    }

    private func rowList(_ rows: [NotificationRow]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(rows) { row in
                NotificationRowView(row: row, open: row.destination.map { destination in
                    { router.openFromScreen(destination) }
                })
            }
        }
        .accessibilityIdentifier("notifications.rows")
    }

    /// The screen is the one the member sees: on top of its tab's stack, the tab selected.
    private var isOnScreen: Bool {
        guard let shellTab else { return true }
        return router.selectedTab == shellTab && router.path(shellTab).last == .notifications
    }

    /// An empty first page that still has more pages: the next ones load (rows the server could not
    /// write are left out of a page, §7 G15); the empty state only once none is left.
    @ViewBuilder
    private var emptyContent: some View {
        if model.isLoadingPastEmptyPages {
            if let error = model.list.loadMoreError {
                VStack(spacing: TaleedSpacing.s8) {
                    Text(l10n.message(for: error))
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textBody)
                        .multilineTextAlignment(.center)
                    TaleedButton(title: l10n.string(.commonRetry), kind: .tertiary, size: .medium) {
                        Task { await model.loadPastEmptyPages() }
                    }
                }
                .padding(TaleedSpacing.s16)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(TaleedColor.brandPrimary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityLabel(l10n.string(.commonLoading))
            }
        } else {
            EmptyState(title: l10n.string(.notificationsEmpty), icon: .bell)
                .padding(.horizontal, TaleedLayout.screenMargin)
                .accessibilityIdentifier("notifications.empty")
        }
    }
}

/// A notification: the 2 pt primary bar on the leading side when unread (the website's), the type's
/// icon in a 40 pt circle, the server's sentence (medium and dark when unread, muted when read) and the
/// relative time under it. A row with a link is a button as a whole; a row without one is plain.
struct NotificationRowView: View {
    let row: NotificationRow
    let open: (() -> Void)?
    @Environment(LanguageManager.self) private var l10n

    private var isUnread: Bool { !row.isRead }

    var body: some View {
        Group {
            if let open {
                Button(action: open) { content }
                    .buttonStyle(NotificationRowButtonStyle())
            } else {
                content
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1)
                .padding(.leading, TaleedLayout.screenMargin + 40 + TaleedSpacing.s12)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(open == nil ? [] : .isButton)
        .accessibilityIdentifier("notifications.row.\(row.id)")
    }

    private var content: some View {
        HStack(alignment: .top, spacing: TaleedSpacing.s12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.text)
                    .taleedFont(isUnread ? TaleedFont.bodyRegular.with(weight: .medium) : TaleedFont.bodyRegular)
                    .foregroundStyle(isUnread ? TaleedColor.textPrimary : TaleedColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(RelativeTimeText.string(for: row.createdAt, locale: l10n.language.formattingLocale))
                    .taleedFont(TaleedFont.meta)
                    .foregroundStyle(isUnread ? TaleedColor.brandPrimary : TaleedColor.textSecondary)
            }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
        .padding(.vertical, TaleedSpacing.s12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .overlay(alignment: .leading) {
            if isUnread {
                Rectangle()
                    .fill(TaleedColor.brandPrimary)
                    .frame(width: 2)
                    .padding(.vertical, TaleedSpacing.s12)
            }
        }
        .contentShape(Rectangle())
    }

    private var icon: some View {
        TaleedIconView(row.theme.icon, size: 20, color: isUnread ? TaleedColor.brandPrimary : TaleedColor.textSecondary)
            .frame(width: 40, height: 40)
            .background(Circle().fill(isUnread ? TaleedColor.brandSoft : TaleedColor.surfaceGrouped))
            .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        var parts = [row.text, RelativeTimeText.string(for: row.createdAt, locale: l10n.language.formattingLocale)]
        if isUnread { parts.insert(l10n.string(.appA11yUnread), at: 0) }
        return parts.joined(separator: ", ")
    }
}

/// The row's pressed state: the grouped surface, as the design-system list rows.
private struct NotificationRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? TaleedColor.surfaceGrouped : TaleedColor.surfacePrimary)
    }
}
