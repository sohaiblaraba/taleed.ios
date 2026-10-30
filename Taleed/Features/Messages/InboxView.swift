import SwiftUI

/// The Messages tab (screens.md §2 G9 and §7 G9; no Figma screen, decision D-12): the app bar
/// "Messages", then the inbox signed in, or "Sign in to continue" signed out.
struct MessagesView: View {
    @Environment(LanguageManager.self) private var l10n
    @Environment(SessionManager.self) private var session
    @Environment(\.messagesDependencies) private var dependencies

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.tabMessages))
        } content: {
            if session.isSignedIn, let dependencies {
                // A new list for another member.
                InboxView(api: dependencies.messages, reads: dependencies.reads).id(session.user?.id)
            } else {
                // The empty-state pattern of the app's other prompts: icon, title, body, "Se connecter".
                SignInPromptView(icon: .chatCircleText, title: l10n.string(.appChatSignedOutTitle))
            }
        }
    }
}

/// The inbox (`GET /conversations`): the Tous / Achats / Ventes filter, then one row per conversation,
/// most recent first. States: loading, the error with Retry (offline included), "Aucune conversation",
/// pull-to-refresh and the pagination footer; a quiet reload on return to the foreground, when the
/// member comes back to it and when a message push arrives.
struct InboxView: View {
    @State private var model: InboxViewModel
    let reads: ConversationReads
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(SessionManager.self) private var session
    @Environment(PushNotificationCenter.self) private var pushes
    @Environment(\.scenePhase) private var scenePhase

    init(api: MessagesApi, reads: ConversationReads) {
        self.reads = reads
        _model = State(initialValue: InboxViewModel(api: api))
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.list.hasLoaded, !model.isEmpty {
                TaleedTabs(titles: InboxFilter.allCases.map(title), selection: filterSelection)
                    .accessibilityIdentifier("inbox.filter")
            }
            PagedListView(list: model.list, centersEmpty: true, placeholder: AnyView(SkeletonConversationList())) { _ in
                let rows = model.visibleItems
                if rows.isEmpty, !model.list.hasMore {
                    // Centred in the list's space, as the error state.
                    emptyState
                        .padding(TaleedSpacing.s24)
                        .frame(maxWidth: .infinity)
                        .containerRelativeFrame(.vertical)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { conversation in
                            InboxRow(conversation: conversation) {
                                router.push(.conversation(id: conversation.id))
                            }
                        }
                    }
                }
            } empty: {
                emptyState
            }
            .accessibilityIdentifier("inbox.list")
        }
        // Back on the inbox: a conversation with news moves to the top, a read one loses its counter.
        .onChange(of: isOnScreen) { _, onScreen in
            if onScreen { Task { await refresh() } }
        }
        // A message push while the inbox shows: the conversation moves to the top (slice C).
        .onChange(of: pushes.messageArrivals) { _, _ in
            if isOnScreen { Task { await refresh() } }
        }
        // A conversation was read (here or from another tab): its row clears at once, even when the quiet
        // reload on the way back is skipped as too recent.
        .onChange(of: reads.latest) { _, mark in
            if let mark { model.apply(mark) }
        }
    }

    /// The inbox is the screen the member sees: its tab, nothing pushed on it, the app in the foreground.
    private var isOnScreen: Bool {
        scenePhase == .active && router.selectedTab == .messages && router.path(.messages).isEmpty
    }

    private func refresh() async {
        // A read the list missed while a conversation covered it.
        if let mark = reads.latest { model.apply(mark) }
        await model.reloadQuietly()
        // The tab badge with it (`counts.unreadMessages`).
        await session.refresh()
    }

    private var emptyState: some View {
        EmptyState(title: l10n.string(.chatEmpty), message: l10n.string(.chatEmptyBody), icon: .chatCircleText)
    }

    private var filterSelection: Binding<Int> {
        Binding(get: { model.filter.rawValue }, set: { model.filter = InboxFilter(rawValue: $0) ?? .all })
    }

    private func title(_ filter: InboxFilter) -> String {
        switch filter {
        case .all: l10n.string(.commonAll)
        case .buying: l10n.string(.ordersPurchases)
        case .selling: l10n.string(.ordersSales)
        }
    }
}

/// A conversation in the inbox: the other member (or "Utilisateur supprimé") with the item's thumbnail
/// on their avatar, the time of the last message, the item and its status when no longer for sale, the
/// last message's line, and the unread counter ("9+" above 9). Unread rows are bold.
struct InboxRow: View {
    let conversation: InboxConversation
    let open: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isUnread: Bool { conversation.unreadCount > 0 }

    /// From accessibility text sizes on, the time goes under the name and the item and the last message
    /// take two lines each, so none of them is cut to a few letters.
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: TaleedSpacing.s12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    let header = isLarge
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8))
                    header {
                        ChatMemberName(member: conversation.counterpart,
                                       style: TaleedFont.bodyLarge.with(weight: isUnread ? .bold : .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ChatText.inboxTime(conversation.lastMessageAt, locale: l10n.language.formattingLocale))
                            .taleedFont(TaleedFont.meta)
                            .foregroundStyle(isUnread ? TaleedColor.brandPrimary : TaleedColor.textSecondarySmall)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if let listing = conversation.listing {
                        HStack(spacing: TaleedSpacing.s8) {
                            Text(verbatim: listing.title.isolatedByContent)
                                .taleedFont(TaleedFont.caption)
                                .foregroundStyle(TaleedColor.textSecondarySmall)
                                .lineLimit(isLarge ? 2 : 1)
                            // The 22 pt tag, drawn over the line's own height: a "Vendu" row is as tall
                            // as the others.
                            ChatListingStatusBadge(status: listing.status, size: .compact)
                                .padding(.vertical, -4)
                        }
                    }
                    HStack(spacing: TaleedSpacing.s8) {
                        // Nothing sent yet: the line stays (empty), so every row has one height; the item's
                        // line above says what the conversation is about.
                        Text(verbatim: (conversation.lastMessage?.text ?? " ").isolatedByContent)
                            .taleedFont(isUnread ? TaleedFont.bodyRegular.with(weight: .semibold) : TaleedFont.bodyRegular)
                            .foregroundStyle(isUnread ? TaleedColor.textPrimary : TaleedColor.textBody)
                            .lineLimit(isLarge ? 2 : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isUnread {
                            // "9+" above 9 (§7 G9).
                            CountBadge(count: conversation.unreadCount,
                                       accessibilityLabel: l10n.format(.appBadgeUnreadMessages, conversation.unreadCount), maxCount: 9)
                                // Over the line's height, as the status tag: unread rows keep the same height.
                                .padding(.vertical, -3)
                        }
                    }
                }
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.vertical, TaleedSpacing.s12)
            .frame(maxWidth: .infinity, minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(InboxRowButtonStyle())
        .overlay(alignment: .bottom) {
            // From the text column: margin, the 48 pt avatar, its 4 pt badge room and the 12 pt gap.
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1)
                .padding(.leading, TaleedLayout.screenMargin + 48 + 4 + TaleedSpacing.s12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("inbox.row.\(conversation.id)")
    }

    private var avatar: some View {
        ChatAvatar(member: conversation.counterpart, size: 48)
            .overlay(alignment: .bottomTrailing) {
                if let listing = conversation.listing {
                    RemoteImage(url: listing.imageURL)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(TaleedColor.surfacePrimary, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            }
            .padding(.trailing, 4)
    }

    private var accessibilityText: String {
        var parts = [conversation.counterpart?.displayName ?? l10n.string(.chatDeletedUser)]
        if conversation.counterpart?.isOfficial == true { parts.append(l10n.string(.profileOfficial)) }
        if let listing = conversation.listing {
            parts.append(listing.title)
            if let key = ChatText.listingStatusKey(listing.status) { parts.append(l10n.string(key)) }
        }
        if let text = conversation.lastMessage?.text { parts.append(text) }
        parts.append(RelativeTimeText.string(for: conversation.lastMessageAt, locale: l10n.language.formattingLocale))
        if conversation.unreadCount > 0 { parts.append(l10n.format(.appBadgeUnreadMessages, conversation.unreadCount)) }
        return parts.joined(separator: ", ")
    }
}

/// The row's pressed state: the grouped surface, as the design-system list rows.
private struct InboxRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? TaleedColor.surfaceGrouped : TaleedColor.surfacePrimary)
    }
}
