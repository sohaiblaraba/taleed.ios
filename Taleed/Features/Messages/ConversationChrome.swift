import SwiftUI

/// The conversation's app bar (the 56 pt design-system bar, decision D-1): back, the other member
/// (avatar and handle, opens their profile), and the menu.
struct ConversationAppBar: View {
    let member: ChatMember?
    /// False until the conversation arrives: no identity yet (a nil member means a deleted one).
    var isLoaded = true
    let onBack: () -> Void
    var onProfile: (() -> Void)?
    var menu: [AppBarMenuItem] = []
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(spacing: TaleedSpacing.s4) {
            TaleedIconOnlyButton(icon: .caretLeft, accessibilityLabel: l10n.string(.commonBack), kind: .hyperlink,
                                 size: .medium, action: onBack)
            Group {
                if !isLoaded {
                    Color.clear
                } else if let onProfile {
                    Button(action: onProfile) { identity }
                        .buttonStyle(.plain)
                        .accessibilityHint(l10n.string(.listingViewProfile))
                } else {
                    identity
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !menu.isEmpty {
                Menu {
                    ForEach(menu) { item in
                        Button(item.title, role: item.isDestructive ? .destructive : nil, action: item.action)
                    }
                } label: {
                    TaleedIconView(.dotsThree, size: 20, color: TaleedColor.blue600)
                        .frame(width: 40, height: 40)
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.string(.commonMore))
                .accessibilityIdentifier("conversation.menu")
            }
        }
        .padding(.horizontal, TaleedSpacing.s8)
        .frame(maxWidth: .infinity, minHeight: TaleedSize.appBarHeight)
        .background(TaleedColor.surfacePrimary)
        .overlay(alignment: .bottom) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
    }

    private var identity: some View {
        HStack(spacing: TaleedSpacing.s8) {
            ChatAvatar(member: member, size: 36)
            ChatMemberName(member: member, style: TaleedFont.appBarTitle)
        }
        .frame(minHeight: TaleedSize.touchTargetMin)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The item the conversation is about, under the app bar: thumbnail, title, price and its status when
/// it is no longer for sale. Opens the listing.
struct ConversationListingStrip: View {
    let listing: ChatListing
    let open: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        Button(action: open) {
            HStack(spacing: TaleedSpacing.s12) {
                RemoteImage(url: listing.imageURL)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: listing.title.isolatedByContent)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: TaleedSpacing.s8) {
                        PriceText(amount: listing.price, style: TaleedFont.priceListRow)
                        ChatListingStatusBadge(status: listing.status)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TaleedIconView(.caretRight, size: 18, color: TaleedColor.textSecondary)
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.vertical, TaleedSpacing.s8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(TaleedColor.surfacePrimary)
        .overlay(alignment: .bottom) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityHint(l10n.string(.chatViewListing))
        .accessibilityIdentifier("conversation.listing")
    }
}

/// The composer (screens.md §7 G9): an optional photo, "Écrivez un message…" (2 000 characters at
/// most, it grows to five lines), the photo button and "Envoyer". It sits above the keyboard.
struct ChatComposer: View {
    @Binding var text: String
    let photo: ComposerPhoto?
    let canSend: Bool
    var focus: FocusState<Bool>.Binding
    /// "Faire une offre" or "Proposer un prix" above the field (G10); nil when no offer can be made.
    var offerTitle: String?
    var onOffer: () -> Void = {}
    let onSend: () -> Void
    let onAddPhoto: () -> Void
    let onRemovePhoto: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            if let offerTitle {
                TaleedButton(title: offerTitle, kind: .tertiary, size: .small, leadingIcon: .money, action: onOffer)
                    .accessibilityIdentifier("conversation.offer")
            }
            if let photo { attachedPhoto(photo) }
            HStack(alignment: .bottom, spacing: TaleedSpacing.s8) {
                Button(action: onAddPhoto) {
                    Image(systemName: "photo")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(photo == nil ? TaleedColor.brandPrimary : TaleedColor.textSecondary)
                        .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // One photo per message.
                .disabled(photo != nil)
                .accessibilityLabel(l10n.string(.chatAddPhoto))
                .accessibilityIdentifier("conversation.addPhoto")
                field
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TaleedColor.textInverse)
                        .flipsForRightToLeftLayoutDirection(true)
                        .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                        .background(Circle().fill(canSend ? TaleedColor.brandPrimary : TaleedColor.navy200))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(l10n.string(.commonSend))
                .accessibilityIdentifier("conversation.send")
            }
        }
        .padding(.horizontal, TaleedSpacing.s12)
        .padding(.vertical, TaleedSpacing.s8)
        .background(TaleedColor.surfacePrimary)
        .overlay(alignment: .top) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
        return TextField("", text: $text, prompt: Text(l10n.string(.chatTypeMessage)).foregroundStyle(TaleedColor.textSecondary),
                         axis: .vertical)
            .lineLimit(1...5)
            .taleedFont(TaleedFont.bodyLarge)
            .foregroundStyle(TaleedColor.textPrimary)
            .tint(TaleedColor.brandPrimary)
            .focused(focus)
            .padding(.horizontal, TaleedSize.inputPaddingX)
            .padding(.vertical, 10)
            .frame(minHeight: TaleedSize.inputHeight)
            .background(shape.fill(TaleedColor.surfacePrimary))
            .overlay(shape.strokeBorder(focus.wrappedValue ? TaleedColor.brandPrimary : TaleedColor.borderSubtle,
                                        lineWidth: focus.wrappedValue ? 2 : 1))
            .contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = true }
            .accessibilityLabel(l10n.string(.chatTypeMessage))
            .accessibilityIdentifier("conversation.field")
    }

    private func attachedPhoto(_ photo: ComposerPhoto) -> some View {
        Image(uiImage: photo.preview)
            .resizable()
            .scaledToFill()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            .overlay {
                if photo.isUploading {
                    ZStack {
                        TaleedColor.scrim.clipShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                        ProgressView().tint(TaleedColor.textInverse)
                    }
                    .accessibilityLabel(l10n.string(.commonLoading))
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onRemovePhoto) {
                    TaleedIconView(.x, size: 12, color: TaleedColor.textInverse)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(TaleedColor.imageRemoveScrim))
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel(l10n.string(.chatRemovePhoto))
            }
            .padding(.top, 6)
            .padding(.leading, TaleedSize.touchTargetMin + TaleedSpacing.s8)
    }
}

/// In place of the composer when the conversation takes no reply (slice C): why, and "Débloquer" for
/// the member who blocked.
struct ConversationReadOnlyBar: View {
    let notice: ChatText.ReadOnlyNotice
    var isUnblocking = false
    let onUnblock: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s8) {
            Text(text)
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("conversation.readOnly")
            if case .youBlocked = notice {
                TaleedButton(title: l10n.string(.appProfileUnblock), kind: .tertiary, size: .medium, isLoading: isUnblocking,
                             action: onUnblock)
                    .accessibilityIdentifier("conversation.unblock")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TaleedLayout.screenMargin)
        .padding(.vertical, TaleedSpacing.s12)
        .background(TaleedColor.surfaceGrouped)
        .overlay(alignment: .top) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
    }

    private var text: String {
        switch notice {
        case .official: l10n.string(.chatOfficialReadOnly)
        case let .youBlocked(handle): l10n.format(.appChatYouBlocked, handle.isolatedLeftToRight)
        case .blocked: l10n.string(.chatBlockedReadOnly)
        case .memberDeleted: l10n.string(.chatDeletedReadOnly)
        case .generic: l10n.string(.appChatReadOnly)
        }
    }
}
