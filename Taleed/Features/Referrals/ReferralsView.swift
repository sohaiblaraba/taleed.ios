import SwiftUI

/// Referrals (screens.md §2 and §7 G18; website `referrals/page.tsx`; Figma does not draw it, decision
/// D-12, so it is built from design-system parts): back and "Parrainage", then
/// 1. the hero card: the website's artwork (never cropped), the gift eyebrow, the title and text filled
///    from `program`, and "soumis à des conditions" (the terms in the in-app browser);
/// 2. verified: the invite link, "Copier le lien d’invitation" ("Lien copié !" for 2.5 s), "Partager le
///    lien" (the system share sheet) and the "Vos filleuls (n)" row, which opens the members invited and
///    the vouchers; not verified: the amber box that explains, then "Vérifier mon identité" (identity
///    verification, G17) as a full-width button in the same place as "Copier le lien";
/// 3. "Comment fonctionne le parrainage": the three illustrated steps and the other rules of `program`.
///
/// States: loading (the hero's skeleton), the error with Retry (offline included), pull-to-refresh, a
/// quiet reload back from the background. Signed out: the sign-in prompt.
struct ReferralsView: View {
    let api: ReferralsApi
    @Environment(SessionManager.self) private var session
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if session.isSignedIn {
            // A new screen for another member.
            ReferralsScreen(api: api).id(session.user?.id)
        } else {
            ShellScreen {
                TaleedTopAppBar(title: l10n.string(.referralsTitle), onBack: { dismiss() })
            } content: {
                SignInPromptView(icon: .gift, title: l10n.string(.appReferralsSignedOutTitle))
            }
        }
    }
}

private struct ReferralsScreen: View {
    @State private var model: ReferralsViewModel
    @State private var showsReferrals = false
    /// A screen to open once the "Vos filleuls" sheet is gone.
    @State private var routeAfterSheet: AppRoute?
    /// The height of the sheet's content while it holds only the empty state: the sheet fits it.
    @State private var compactSheetHeight: CGFloat = 420
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router
    @Environment(AppToasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(api: ReferralsApi) {
        _model = State(initialValue: ReferralsViewModel(api: api))
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.referralsTitle), onBack: { dismiss() })
        } content: {
            content
        }
        .task { await model.loadIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.wentToBackground()
            case .active: Task { await model.returnedToForeground() }
            default: break
            }
        }
        .onChange(of: model.notice) { _, notice in
            guard notice != nil else { return }
            model.notice = nil
            // Under the sheet the toast would not show: the sheet shows its own.
            if !showsReferrals { toasts.show(l10n.string(.referralsCopied)) }
        }
        .onChange(of: model.referrals.refreshError) { _, error in
            if let error, !showsReferrals { toasts.show(error: error) }
        }
        .sheet(isPresented: $showsReferrals, onDismiss: openRouteAfterSheet) {
            if let program = model.program {
                ReferralsSheet(model: model, copy: ReferralsCopy(program: program, l10n: l10n),
                               onOpen: { route in
                                   routeAfterSheet = route
                                   showsReferrals = false
                               },
                               onClose: { showsReferrals = false },
                               onCompactHeight: { compactSheetHeight = $0 })
                    .appLanguage(l10n.language)
                    // No member yet: sized to the empty state (the copy toast lands by its buttons); the
                    // full height once there is a list.
                    .presentationDetents(model.isSheetCompact ? [.height(compactSheetHeight)] : [.large])
                    .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(TaleedColor.surfaceElevated)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let program = model.program {
            let copy = ReferralsCopy(program: program, l10n: l10n)
            ScrollView {
                VStack(alignment: .leading, spacing: TaleedSpacing.s24) {
                    ReferralHeroCard(copy: copy) { invitePart(program: program) }
                    ReferralStepsSection(copy: copy)
                }
                .padding(.horizontal, TaleedLayout.screenMargin)
                .padding(.vertical, TaleedSpacing.s16)
            }
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("referrals.scroll")
        } else if let error = model.loadError {
            ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
        } else {
            ScrollView {
                ReferralHeroSkeleton()
                    .padding(.horizontal, TaleedLayout.screenMargin)
                    .padding(.vertical, TaleedSpacing.s16)
            }
            .scrollDisabled(true)
        }
    }

    @ViewBuilder
    private func invitePart(program: ReferralProgramInfo) -> some View {
        switch program.access {
        case let .invite(url):
            VStack(spacing: TaleedSpacing.s12) {
                InviteLinkBox(url: url)
                CopyInviteButton(isCopied: model.isCopied, copy: model.copyInvite)
                ShareInviteButton(url: url)
                YourReferralsRow(title: referralsLinkTitle) { showsReferrals = true }
                    .padding(.top, TaleedSpacing.s4)
            }
        case .gate:
            // The alert explains; the action takes the verified state's main slot, full width.
            VStack(spacing: TaleedSpacing.s12) {
                InlineAlert(kind: .warning, title: l10n.string(.referralsGateTitle), message: l10n.string(.referralsGateBody))
                    .accessibilityIdentifier("referrals.gate")
                TaleedButton(title: l10n.string(.referralsGateCta), kind: .secondary, size: .large, leadingIcon: .shieldCheck,
                             isFullWidth: true) {
                    router.push(.identityVerification)
                }
                .accessibilityIdentifier("referrals.gate.verify")
            }
        case .none:
            EmptyView()
        }
    }

    /// "Vos filleuls", with the API's total once there is one: "Vos filleuls (2)".
    private var referralsLinkTitle: String {
        let title = l10n.string(.referralsYourReferrals)
        guard let count = model.referralCount, count > 0 else { return title }
        return l10n.format(.appMyListingsTabCount, title, count)
    }

    private func openRouteAfterSheet() {
        guard let route = routeAfterSheet else { return }
        routeAfterSheet = nil
        router.push(route)
    }
}

// MARK: - Hero

/// The website's hero, stacked for a phone: the artwork in full, then the text panel and the invite part.
private struct ReferralHeroCard<Invite: View>: View {
    let copy: ReferralsCopy
    @ViewBuilder let invite: Invite
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(taleed: .referralHero)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 240)
                .padding(.top, TaleedSpacing.s16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                HStack(spacing: 6) {
                    TaleedIconView(.gift, size: 14, color: TaleedColor.brandPrimary)
                        .accessibilityHidden(true)
                    Eyebrow(text: copy.eyebrow)
                }
                Text(copy.heroTitle)
                    .taleedFont(TaleedFont.title2.with(weight: .bold))
                    .foregroundStyle(TaleedColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(copy.heroBody)
                    .taleedFont(TaleedFont.bodyRegular)
                    .lineSpacing(4)
                    .foregroundStyle(TaleedColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                termsNote
                invite
                    .padding(.top, TaleedSpacing.s4)
            }
            .padding(TaleedSpacing.s16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaleedColor.surfacePrimary, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous).strokeBorder(TaleedColor.borderSubtle))
    }

    /// "Le programme de parrainage est soumis à des conditions.": the whole line opens the terms (a 44 pt
    /// target, the tagged word still drawn as the link); plain text when there are none.
    @ViewBuilder
    private var termsNote: some View {
        let text = Text(ReferralsCopy.termsNote(l10n.string(.referralsTermsNote), termsURL: copy.program.termsURL,
                                                linkColor: TaleedColor.textPrimary, isLink: false))
            .taleedFont(TaleedFont.bodySmall)
            .foregroundStyle(TaleedColor.textSecondarySmall)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let termsURL = copy.program.termsURL {
            Button { router.openInBrowser(termsURL) } label: {
                text
                    .frame(minHeight: TaleedSize.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -TaleedSpacing.s8)
            .accessibilityAddTraits(.isLink)
            .accessibilityIdentifier("referrals.terms")
        } else {
            text.accessibilityIdentifier("referrals.terms")
        }
    }
}

/// The invite link as text, selectable, left to right in every language.
private struct InviteLinkBox: View {
    let url: URL
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        HStack(spacing: TaleedSpacing.s8) {
            TaleedIconView(.link, size: 18, color: TaleedColor.brandPrimary)
                .accessibilityHidden(true)
            Text(verbatim: url.absoluteString.isolatedLeftToRight)
                .taleedFont(TaleedFont.bodyRegular.with(weight: .semibold))
                .foregroundStyle(TaleedColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TaleedSpacing.s12)
        .frame(minHeight: TaleedSize.touchTargetMin)
        .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedSize.inputRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TaleedSize.inputRadius, style: .continuous).strokeBorder(TaleedColor.borderSubtle))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.string(.appReferralsInviteLink))
        .accessibilityValue(url.absoluteString)
        .accessibilityIdentifier("referrals.inviteLink")
    }
}

/// "Vos filleuls (2)" as a list row at the bottom of the hero card (icon, title with the count, chevron):
/// the way to the members invited, their rewards and the vouchers.
private struct YourReferralsRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TaleedSpacing.s12) {
                TaleedIconView(.user, size: 18, color: TaleedColor.brandPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(TaleedColor.brandSoft))
                    .accessibilityHidden(true)
                Text(title)
                    .taleedFont(TaleedFont.bodyRegular.with(weight: .semibold))
                    .foregroundStyle(TaleedColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TaleedIconView(.caretRight, size: 16, color: TaleedColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(TaleedSpacing.s12)
            .frame(minHeight: TaleedSize.touchTargetMin)
            .contentShape(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        }
        .buttonStyle(ReferralRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("referrals.yourReferrals")
    }
}

/// The row's card, the grouped surface while pressed.
private struct ReferralRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .taleedCard(fill: configuration.isPressed ? TaleedColor.surfaceGrouped : TaleedColor.surfacePrimary)
    }
}

/// "Copier le lien d’invitation" (mint CTA, the copy glyph), "Lien copié !" with a check for 2.5 s after a copy.
struct CopyInviteButton: View {
    let isCopied: Bool
    let copy: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        TaleedButton(title: l10n.string(isCopied ? .referralsCopied : .referralsCopyCta), kind: .secondary, size: .large,
                     leadingIcon: isCopied ? .check : .copy, isFullWidth: true, action: copy)
            .accessibilityIdentifier("referrals.copy")
    }
}

/// "Partager le lien": the system share sheet with `inviteUrl` (slice E). Its preview carries its own
/// title and the Taleed mark, so the sheet shows at once instead of fetching the page's (English) title.
struct ShareInviteButton: View {
    let url: URL
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ShareLink(item: url, preview: SharePreview(l10n.string(.appReferralsSharePreviewTitle), image: Image(taleed: .lettermark))) {
            HStack(spacing: TaleedSize.buttonGap) {
                TaleedIconView(.shareNetwork, size: TaleedButtonSize.large.iconSize, color: nil)
                Text(l10n.string(.appReferralsShare))
                    .taleedFont(TaleedButtonSize.large.textStyle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(TaleedButtonStyle(kind: .tertiary, size: .large, isFullWidth: true))
        .accessibilityLabel(l10n.string(.appReferralsShare))
        .accessibilityIdentifier("referrals.share")
    }
}
