import SwiftUI

/// The messages of a conversation, newest at the bottom: drawn upside down (`flippedForChat`) so that
/// the list starts at the newest message and older pages load at the top as the member scrolls up.
struct ConversationMessageList: View {
    let model: ConversationViewModel
    let isOfficial: Bool
    let openPhoto: (URL) -> Void
    let openLink: (URL) -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router

    var body: some View {
        let rows = model.rows()
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: TaleedSpacing.s8) {
                    ForEach(rows) { row in
                        self.row(row)
                            .flippedForChat()
                            .id(row.id)
                    }
                    olderFooter.flippedForChat()
                }
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.vertical, TaleedSpacing.s12)
            }
            .flippedForChat()
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("conversation.messages")
            // A bubble the member just sent: back to the newest message.
            .onChange(of: model.outgoing.first?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: TaleedMotion.transitionMin)) { proxy.scrollTo("out-\(id)", anchor: .top) }
            }
        }
    }

    /// The top of the list: the older page loads when it shows; "Réessayer" when it failed.
    @ViewBuilder
    private var olderFooter: some View {
        if model.olderError != nil {
            VStack(spacing: TaleedSpacing.s8) {
                Text(l10n.string(.appListLoadMoreFailed))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textBody)
                    .multilineTextAlignment(.center)
                TaleedButton(title: l10n.string(.commonRetry), kind: .tertiary, size: .medium) {
                    Task { await model.loadOlder() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(TaleedSpacing.s16)
        } else if model.hasOlder {
            ProgressView()
                .tint(TaleedColor.brandPrimary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .accessibilityLabel(l10n.string(.commonLoading))
                .task(id: model.messages.count) { await model.loadOlder() }
        }
    }

    @ViewBuilder
    private func row(_ row: ChatRow) -> some View {
        switch row {
        case let .day(date):
            ChatDayLabel(date: date)
        case let .outgoing(message):
            VStack(alignment: .trailing, spacing: TaleedSpacing.s4) {
                ChatBubbleRow(isMine: true) {
                    ChatBubble(content: ChatBubbleContent(photo: message.photo.map(ChatBubblePhoto.local), text: message.draft.text,
                                                          time: ChatText.time(message.createdAt, locale: l10n.language.formattingLocale)),
                               isMine: true)
                        .opacity(message.state == .sending ? 0.7 : 1)
                }
                OutgoingStatus(state: message.state) { Task { await model.retry(message.id) } }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("conversation.outgoing")
        case let .message(message):
            messageRow(message)
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.kind {
        case .text:
            ChatBubbleRow(isMine: message.isMine, widthShare: isOfficial ? 0.85 : 0.75) {
                ChatBubble(content: bubbleContent(message), isMine: message.isMine,
                           openPhoto: openPhoto, openLink: openLink)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(message.isMine ? l10n.string(.commonYou) : senderName)
        case .offer:
            ChatSideRow(isMine: message.isMine) {
                if let offer = model.offer(in: message) {
                    ChatOfferCard(offer: offer, isMine: message.isMine, openListing: { router.push(.listing(id: $0)) })
                }
            }
        case .bundle:
            ChatSideRow(isMine: message.isMine) {
                if let bundle = message.bundle {
                    ChatBundleCard(bundle: bundle, isMine: message.isMine, openListing: { router.push(.listing(id: $0)) })
                }
            }
        case .orderUpdate:
            ChatOrderPill(text: message.text ?? "", order: message.order) { router.pushSignedIn(.order(id: $0)) }
        case .offerUpdate, .system, .unknown:
            ChatPill(text: message.text ?? "")
        }
    }

    private var senderName: String {
        model.conversation?.counterpart?.displayName ?? l10n.string(.chatDeletedUser)
    }

    private func bubbleContent(_ message: ChatMessage) -> ChatBubbleContent {
        let announcement = message.html.map { AnnouncementHTML.blocks(from: $0, baseURL: router.websiteLinks().website) } ?? []
        return ChatBubbleContent(
            photo: message.photoURL.map(ChatBubblePhoto.remote),
            text: message.text,
            announcement: announcement,
            callToAction: message.callToAction,
            time: ChatText.time(message.createdAt, locale: l10n.language.formattingLocale)
        )
    }
}
