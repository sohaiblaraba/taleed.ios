import SwiftUI

/// The dispute thread (screens.md §2 G12 screen 5 and §7 G12; slice D "The thread"; website
/// `dispute-thread.tsx`): back and "Fil du litige"; the dispute's status, reason and order, who must
/// answer until when while it is open, and how it ended; the whole thread oldest first, the member's
/// own messages at the end side, Taleed support apart with its shield; the seller's "Accepter la
/// réclamation" (after a confirmation) and "Contester" while `canRespond` (G13); then, while `canPost`, the
/// notice that buyer, seller and support see every message, and the composer (text, up to 4 photos);
/// otherwise "Le litige est résolu — la discussion est close."
///
/// States: loading, error with Retry (offline included), "no longer available" (`404`), pull-to-refresh
/// and reload on return to the foreground (there is no live stream).
struct DisputeThreadView: View {
    @State private var model: DisputeThreadViewModel
    @State private var viewer: PhotoViewerState?
    @State private var confirmsAccept = false
    @FocusState private var isComposerFocused: Bool
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.shellTab) private var shellTab
    private let route: AppRoute

    struct PhotoViewerState: Identifiable {
        let id = UUID()
        let photos: [ListingPhoto]
        let index: Int
    }

    init(disputeId: String, dependencies: OrdersDependencies) {
        route = .dispute(id: disputeId)
        _model = State(initialValue: DisputeThreadViewModel(
            disputeId: disputeId, api: dependencies.orders,
            upload: { [uploads = dependencies.uploads] data throws(ApiError) in
                try await uploads.upload(data, purpose: .disputeEvidence)
            }
        ))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.disputesThread), onBack: { dismiss() })
        } content: {
            content
        }
        .task { await model.loadIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.dispute != nil { Task { await model.reload(automatic: true) } }
        }
        .onChange(of: model.notice) { _, error in
            guard let error else { return }
            model.notice = nil
            toasts.show(error: error)
        }
        .onChange(of: model.success) { _, key in
            guard let key else { return }
            model.success = nil
            toasts.show(l10n.string(key))
        }
        .taleedConfirmation(isPresented: confirmsAccept) {
            ConfirmationModalCard(title: l10n.string(.disputesAcceptClaim), message: l10n.string(.disputesAcceptClaimHint),
                                  confirmTitle: l10n.string(.disputesAcceptClaim),
                                  onConfirm: {
                                      confirmsAccept = false
                                      Task { await model.answer(.accept) }
                                  },
                                  onCancel: { confirmsAccept = false },
                                  icon: .checkCircle, tone: .positive)
        }
        .fullScreenCover(item: $viewer) { state in
            ListingPhotoViewer(photos: state.photos, current: state.index)
                .appLanguage(l10n.language)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let dispute = model.dispute {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                            DisputeHeaderCard(dispute: dispute) { router.pushOrGoBack(to: .order(id: dispute.orderId)) }
                            if dispute.canRespond {
                                DisputeAnswerButtons(answering: model.answering, isDisabled: model.isSending,
                                                     onAccept: { confirmsAccept = true },
                                                     onContest: { Task { await model.answer(.contest) } })
                            }
                            ForEach(dispute.messages) { message in
                                DisputeMessageBubble(message: message) { index in
                                    viewer = PhotoViewerState(
                                        photos: message.photoURLs.enumerated().map {
                                            ListingPhoto(id: "\($0.offset)", url: $0.element, thumbURL: $0.element)
                                        },
                                        index: index
                                    )
                                }
                                .id(message.id)
                            }
                        }
                        .padding(.top, TaleedSpacing.s16)
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.bottom, TaleedSpacing.s24)
                    }
                    .refreshable { await model.reload() }
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("dispute.scroll")
                    .onChange(of: model.postedCount) { _, _ in
                        if let last = dispute.messages.last?.id {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
                footer(dispute)
                    // Toasts show above the composer while this screen is on top.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if let shellTab { toasts.setBottomBarHeight(height, tab: shellTab, route: route) }
                    }
            }
        } else if let error = model.loadError {
            if error.isNotFound {
                NotFoundStateView(onBack: { dismiss() })
            } else {
                ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
            }
        } else {
            LoadingStateView()
        }
    }

    @ViewBuilder
    private func footer(_ dispute: DisputeInfo) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            if dispute.canPost {
                Text(l10n.string(.disputesThreadHint))
                    .taleedFont(TaleedFont.caption)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.photos.items.isEmpty {
                    EvidencePhotosRow(photos: model.photos, isDisabled: model.isSending)
                }
                if let failed = model.photos.firstError {
                    FieldHelper(text: l10n.message(for: failed), color: TaleedColor.feedbackError)
                }
                composer
            } else {
                Text(l10n.string(.disputesThreadClosed))
                    .taleedFont(TaleedFont.bodySmall)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("dispute.closed")
            }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
        .padding(.top, TaleedSpacing.s12)
        .bottomBarPadding(TaleedSpacing.s12)
        .bottomBarBackground(TaleedColor.surfacePrimary)
        .overlay(alignment: .top) { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
    }

    /// The text field, the photo button (while fewer than 4) and "Envoyer".
    private var composer: some View {
        HStack(alignment: .bottom, spacing: TaleedSpacing.s8) {
            // The placeholder wraps (a prompt would be cut to one line: "Écrivez votre réponse ou ajo…").
            ZStack(alignment: .topLeading) {
                Text(l10n.string(.disputesReplyPlaceholder))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(model.draft.isEmpty ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                TextField("", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .tint(TaleedColor.brandPrimary)
                    .focused($isComposerFocused)
            }
                .padding(.horizontal, TaleedSpacing.s12)
                .padding(.vertical, 10)
                .frame(minHeight: TaleedSize.touchTargetMin)
                .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                .disabled(model.isSending)
                .accessibilityLabel(l10n.string(.disputesReplyPlaceholder))
                .accessibilityIdentifier("dispute.composer")
            if model.photos.items.isEmpty {
                ComposerPhotoButton(photos: model.photos, isDisabled: model.isSending)
            }
            TaleedButton(title: l10n.string(.disputesSend), kind: .primary, size: .medium, isLoading: model.isSending) {
                Task {
                    if await model.send() { isComposerFocused = false }
                }
            }
            .disabled(!model.canSend)
            .accessibilityIdentifier("dispute.send")
        }
    }
}

/// The 44 pt photo button of the composer (the system photo picker); once photos are picked, the
/// row above the composer shows them with its own "+".
private struct ComposerPhotoButton: View {
    let photos: EvidencePhotos
    let isDisabled: Bool
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        EvidencePickerButton(photos: photos, isDisabled: isDisabled) {
            TaleedIconView(.plus, size: 20, color: TaleedColor.brandPrimary)
                .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                .background(TaleedColor.blue50, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        }
        .accessibilityLabel(l10n.string(.disputesAddPhotos))
        .accessibilityIdentifier("dispute.composerPhoto")
    }
}

/// The seller's answer to the claim (`canRespond`): "Accepter la réclamation", which asks first, and
/// "Contester" (no confirmation, as on the website).
private struct DisputeAnswerButtons: View {
    let answering: DisputeAnswerChoice?
    let isDisabled: Bool
    let onAccept: () -> Void
    let onContest: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(spacing: TaleedSpacing.s12) {
            TaleedButton(title: l10n.string(.disputesAcceptClaim), kind: .secondary, size: .large, leadingIcon: .checkCircle,
                         isLoading: answering == .accept, isFullWidth: true, action: onAccept)
                .accessibilityIdentifier("dispute.acceptClaim")
            TaleedButton(title: l10n.string(.disputesContestClaim), kind: .outline, size: .large, leadingIcon: .shieldCheck,
                         isLoading: answering == .contest, isFullWidth: true, action: onContest)
                .accessibilityIdentifier("dispute.contestClaim")
        }
        .disabled(isDisabled || answering != nil)
    }
}

/// The dispute's status, reason and order number (opens the order), who answers until when while it
/// is open, and how it ended.
private struct DisputeHeaderCard: View {
    let dispute: DisputeInfo
    let onOpenOrder: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            HStack(spacing: TaleedSpacing.s8) {
                TaleedBadge(title: dispute.statusLabel, tone: tone)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dispute.status")
                Spacer(minLength: 0)
                Button(action: onOpenOrder) {
                    Text(l10n.format(.ordersOrderNumber, dispute.orderNumber.isolatedLeftToRight))
                        .taleedFont(TaleedFont.bodySmall.with(weight: .semibold))
                        .foregroundStyle(TaleedColor.brandPrimary)
                        .frame(minHeight: TaleedSize.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text(dispute.reasonLabel)
                .taleedFont(TaleedFont.bodyLarge.with(weight: .semibold))
                .foregroundStyle(TaleedColor.textPrimary)
            if dispute.status == .open, let deadline = dispute.sellerDeadlineAt {
                Text(l10n.format(dispute.side == .seller ? .disputesAwaitingYou : .disputesAwaitingSeller,
                                 OrderText.dateTime(deadline, locale: l10n.language.formattingLocale)))
                    .taleedFont(TaleedFont.bodySmall)
                    .foregroundStyle(TaleedColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let resolution = dispute.resolution {
                VStack(alignment: .leading, spacing: 2) {
                    // Verbatim: interpolating into a literal isolates both parts, laid out left to right in Arabic.
                    Text(verbatim: "\(l10n.string(.disputesResolution)): \(resolution)")
                        .taleedFont(TaleedFont.bodySmall)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let resolvedAt = dispute.resolvedAt {
                        Text(OrderText.dateTime(resolvedAt, locale: l10n.language.formattingLocale))
                            .taleedFont(TaleedFont.caption)
                            .foregroundStyle(TaleedColor.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(TaleedSpacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .taleedCard()
    }

    private var tone: TaleedTone {
        switch dispute.status {
        case .open, .underReview: .warning
        case .resolvedRefund, .resolvedRelease: .success
        case .unknown: .neutral
        }
    }
}

/// A message: the author's handle (or "Compte supprimé"), the role chip from the server, the date,
/// the text and the photos (tap: full screen). The member's own messages sit at the end side on the
/// brand tint; Taleed support's have a brand border and a shield on their chip.
private struct DisputeMessageBubble: View {
    let message: DisputeMessageInfo
    let onPhoto: (Int) -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: TaleedSpacing.s48) }
            VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
                header
                if !message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(verbatim: message.body)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .naturalDirection(of: message.body)
                        .textSelection(.enabled)
                }
                if !message.photoURLs.isEmpty {
                    photos
                }
            }
            .padding(TaleedSpacing.s12)
            .background(message.isMine ? TaleedColor.blue50 : TaleedColor.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
                    .strokeBorder(message.role == .support ? TaleedColor.brandPrimary : TaleedColor.borderSubtle,
                                  lineWidth: message.role == .support ? 1.5 : 1)
            }
            if !message.isMine { Spacer(minLength: TaleedSpacing.s48) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dispute.message.\(message.id)")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8) {
            Text(verbatim: message.authorName?.isolatedLeftToRight ?? l10n.string(.ordersDeletedAccount))
                .taleedFont(TaleedFont.bodySmall.with(weight: .semibold))
                .foregroundStyle(TaleedColor.textPrimary)
                .lineLimit(1)
            roleChip
            Spacer(minLength: 0)
            Text(OrderText.dateTime(message.createdAt, locale: l10n.language.formattingLocale))
                .taleedFont(TaleedFont.caption)
                .foregroundStyle(TaleedColor.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var roleChip: some View {
        if message.role == .support {
            HStack(spacing: 2) {
                TaleedIconView(.shieldCheck, size: 12, color: TaleedColor.textInverse)
                Text(message.roleLabel).taleedFont(TaleedFont.tagLabel)
            }
            .foregroundStyle(TaleedColor.textInverse)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(TaleedColor.brandPrimary, in: RoundedRectangle(cornerRadius: TaleedRadius.xs, style: .continuous))
            .fixedSize()
        } else {
            TaleedBadge(title: message.roleLabel, tone: .neutral).fixedSize()
        }
    }

    private var photos: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 112), spacing: TaleedSpacing.s8)],
                  alignment: .leading, spacing: TaleedSpacing.s8) {
            ForEach(Array(message.photoURLs.enumerated()), id: \.offset) { index, url in
                Button { onPhoto(index) } label: {
                    RemoteImage(url: url)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(minWidth: 88, maxWidth: 112)
                        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.s, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.string(.disputesEvidence))
            }
        }
    }
}
