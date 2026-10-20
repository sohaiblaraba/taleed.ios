import NukeUI
import SwiftUI

// The pieces of the conversation screen, from design-system tokens (decision D-12: Messages has no
// Figma screen): the member's avatar, the bubbles, the pills, the offer and bundle cards, the day.

extension View {
    /// The conversation list is drawn upside down so that it starts at the newest message and older
    /// pages load at the top without a jump; each row is flipped back. Only vertically: Arabic keeps
    /// its own right-to-left layout.
    func flippedForChat() -> some View {
        scaleEffect(x: 1, y: -1, anchor: .center)
    }
}

/// A member's avatar, or the placeholder of a deleted member (screens.md §0.3).
struct ChatAvatar: View {
    let member: ChatMember?
    var size: CGFloat = 48

    var body: some View {
        if let member {
            TaleedAvatar(initials: TaleedAvatar.initials(from: member.username ?? member.displayName), size: size,
                         imageURL: member.avatarURL, isVerified: member.isVerified && !member.isOfficial, style: .wireframe)
        } else {
            Circle()
                .fill(TaleedColor.surfaceGrouped)
                .overlay { TaleedIconView(.user, size: size * 0.45, color: TaleedColor.textSecondary) }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// "@amina" with the official seal, or "Utilisateur supprimé".
struct ChatMemberName: View {
    let member: ChatMember?
    var style: TaleedTextStyle = TaleedFont.bodyLarge.with(weight: .bold)
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(spacing: TaleedSpacing.s4) {
            if let member {
                Text(verbatim: member.displayName.isolatedLeftToRight)
                    .taleedFont(style)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .lineLimit(1)
                // The official badge replaces the verified one (screens.md §0.3).
                if member.isOfficial {
                    TaleedIconView(.sealCheck, size: 16, color: TaleedColor.brandPrimary)
                        .accessibilityLabel(l10n.string(.profileOfficial))
                }
            } else {
                Text(l10n.string(.chatDeletedUser))
                    .taleedFont(style)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

/// The badge of a listing that is no longer for sale ("Réservé", "Vendu", "Indisponible").
struct ChatListingStatusBadge: View {
    let status: ChatListingStatus
    var size: TaleedBadge.Size = .regular
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        if let key = ChatText.listingStatusKey(status) {
            TaleedBadge(title: l10n.string(key), tone: ChatText.listingStatusTone(status), size: size)
                .fixedSize()
        }
    }
}

/// The day above its messages.
struct ChatDayLabel: View {
    let date: Date
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        Text(ChatText.day(date, locale: l10n.language.formattingLocale))
            .taleedFont(TaleedFont.caption)
            .foregroundStyle(TaleedColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TaleedSpacing.s8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A centered status pill: an offer answered, an order step, an automatic notice. The text comes from
/// the server, in the response language. A pill that opens something (an order) says so: brand text and
/// a caret after it. Its 44 pt target reaches past the pill without spacing the column out.
struct ChatPill: View {
    let text: String
    var action: (() -> Void)?

    var body: some View {
        let isLink = action != nil
        let pill = HStack(spacing: TaleedSpacing.s4) {
            Text(text)
                .taleedFont(TaleedFont.caption)
                .foregroundStyle(isLink ? TaleedColor.brandPrimary : TaleedColor.textBody)
                .multilineTextAlignment(.center)
            if isLink {
                TaleedIconView(.caretRight, size: 12, color: TaleedColor.brandPrimary)
            }
        }
        .padding(.horizontal, TaleedSpacing.s12)
        .padding(.vertical, 6)
        .background(Capsule().fill(TaleedColor.surfacePrimary))
        .overlay(Capsule().strokeBorder(isLink ? TaleedColor.brandSoftBorder : TaleedColor.borderSubtle))
        HStack {
            if let action {
                Button(action: action) {
                    pill
                        .contentShape(Capsule())
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isLink)
            } else {
                pill
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// An order step (`ORDER_UPDATE`): the pill opens the order; a completed order also asks for a review
/// ("Évaluez votre expérience", §7 G9).
struct ChatOrderPill: View {
    let text: String
    let order: ChatOrderRef?
    let openOrder: (String) -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s8) {
            ChatPill(text: text, action: order.map { order in { openOrder(order.id) } })
            if let order, order.milestone == .completed {
                TaleedButton(title: l10n.string(.chatOrderReviewCta), kind: .tertiary, size: .small, leadingIcon: .star) {
                    openOrder(order.id)
                }
            }
        }
    }
}

/// The bubble's colours: the member's own in brand blue, the other member's on the grouped surface.
enum ChatBubbleStyle {
    static func fill(isMine: Bool) -> Color { isMine ? TaleedColor.brandPrimary : TaleedColor.surfaceGrouped }
    static func text(isMine: Bool) -> Color { isMine ? TaleedColor.textInverse : TaleedColor.textPrimary }
    static func meta(isMine: Bool) -> Color { isMine ? TaleedColor.textInverse.opacity(0.8) : TaleedColor.textSecondary }
    static let shape = RoundedRectangle(cornerRadius: TaleedRadius.l, style: .continuous)
}

/// What a bubble holds: a photo, words (or an announcement's blocks), a button, the time.
struct ChatBubbleContent {
    var photo: ChatBubblePhoto?
    var text: String?
    var announcement: [AnnouncementBlock] = []
    var callToAction: ChatCallToAction?
    /// Nil while the message is not sent yet: no time until the server has it.
    let time: String?
}

enum ChatBubblePhoto {
    case remote(URL)
    case local(UIImage)
}

/// How a bubble on its way looks: sent, still sending (faded), or not sent (faded, red outline).
enum ChatBubbleDelivery {
    case sent, sending, failed
}

/// A `TEXT` message: on the trailing side when it is the member's, at most 75 % of the width (85 % for
/// an announcement).
struct ChatBubble: View {
    let content: ChatBubbleContent
    let isMine: Bool
    var delivery: ChatBubbleDelivery = .sent
    var openPhoto: ((URL) -> Void)?
    var openLink: ((URL) -> Void)?
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        // Sized to its content (a short message makes a short bubble). Words and captions start on the
        // leading edge as text messages do; the time ends on the bubble's side.
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            if let photo = content.photo { photoView(photo) }
            if !content.announcement.isEmpty {
                AnnouncementView(blocks: content.announcement, color: ChatBubbleStyle.text(isMine: isMine))
            } else if let text = content.text {
                Text(verbatim: text.isolatedByContent)
                    .taleedFont(TaleedFont.bodyLarge)
                    .foregroundStyle(ChatBubbleStyle.text(isMine: isMine))
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    // Lines follow the message's own script (Latin from the left, Arabic from the right),
                    // whatever the app language, as the inbox preview.
                    .environment(\.layoutDirection, text.naturalLayoutDirection ?? l10n.language.layoutDirection)
            }
            if let cta = content.callToAction, let url = cta.url {
                TaleedButton(title: cta.label, kind: .primary, size: .small) { openLink?(url) }
            }
            if let time = content.time {
                if isMine {
                    // Holds the row; the time itself is drawn at the trailing edge below.
                    timeText(time).hidden()
                } else {
                    timeText(time)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isMine, let time = content.time { timeText(time) }
        }
        .padding(.horizontal, TaleedSpacing.s12)
        .padding(.vertical, TaleedSpacing.s8)
        .background(ChatBubbleStyle.fill(isMine: isMine), in: ChatBubbleStyle.shape)
        .opacity(delivery == .sent ? 1 : delivery == .sending ? 0.7 : 0.55)
        .overlay {
            if delivery == .failed { ChatBubbleStyle.shape.strokeBorder(TaleedColor.feedbackError, lineWidth: 1.5) }
        }
        .environment(\.openURL, OpenURLAction { url in
            openLink?(url)
            return .handled
        })
    }

    private func timeText(_ time: String) -> some View {
        Text(time)
            .taleedFont(TaleedFont.meta)
            .foregroundStyle(ChatBubbleStyle.meta(isMine: isMine))
    }

    @ViewBuilder
    private func photoView(_ photo: ChatBubblePhoto) -> some View {
        switch photo {
        case let .remote(url):
            Button { openPhoto?(url) } label: {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().scaledToFit()
                    } else {
                        Rectangle().fill(TaleedColor.skeleton).frame(width: 200, height: 200)
                    }
                }
                .frame(maxWidth: 240, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l10n.string(.chatPhotoAlt))
            .accessibilityHint(l10n.string(.appA11yOpenPhoto))
        case let .local(image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                .accessibilityLabel(l10n.string(.chatPhotoAlt))
        }
    }
}

/// A bubble's side and width: the member's on the trailing side.
struct ChatBubbleRow<Content: View>: View {
    let isMine: Bool
    var widthShare: CGFloat = 0.75
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            if isMine { Spacer(minLength: 0) }
            content
                .containerRelativeFrame(.horizontal, alignment: isMine ? .trailing : .leading) { width, _ in
                    width * widthShare
                }
            if !isMine { Spacer(minLength: 0) }
        }
    }
}

/// The status under a bubble on its way: "Envoi…", or "Non envoyé" with "Réessayer".
struct OutgoingStatus: View {
    let state: OutgoingMessage.State
    let retry: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(spacing: TaleedSpacing.s8) {
            switch state {
            case .sending:
                TaleedIconView(.clock, size: 14, color: TaleedColor.textSecondary)
                Text(l10n.string(.appChatSending))
                    .taleedFont(TaleedFont.meta)
                    .foregroundStyle(TaleedColor.textSecondary)
            case .failed:
                TaleedIconView(.warningCircle, size: 14, color: TaleedColor.feedbackError)
                Text(l10n.string(.appChatNotSent))
                    .taleedFont(TaleedFont.meta)
                    .foregroundStyle(TaleedColor.feedbackError)
                TaleedButton(title: l10n.string(.commonRetry), kind: .hyperlink, size: .small, action: retry)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
