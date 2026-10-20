import SwiftUI

/// Referrals (screens.md §2 and §7 G18; website `referrals/page.tsx`; Figma does not draw it, decision
/// D-12, so it is built from design-system parts): back and "Parrainage", then
/// 1. the hero card: the website's artwork (never cropped), the gift eyebrow, the title and text filled
///    from `program`, and "soumis à des conditions" (the terms in the in-app browser);
/// 2. verified: the invite link, "Copier le lien d’invitation" ("Lien copié !" for 2.5 s), "Partager le
///    lien" (the system share sheet) and "Vos filleuls (n)", which opens the members invited and the
///    vouchers; not verified: the amber box with "Vérifier mon identité" (identity verification, G17);
/// 3. "Comment fonctionne le parrainage": the three illustrated steps and the other rules of `program`.
///
/// States: loading, the error with Retry (offline included), pull-to-refresh, a quiet reload back from
/// the background.
struct ReferralsView: View {
    @State private var model: ReferralsViewModel
    @State private var showsReferrals = false
    /// A screen to open once the "Vos filleuls" sheet is gone.
    @State private var routeAfterSheet: AppRoute?
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
                               onClose: { showsReferrals = false })
                    .appLanguage(l10n.language)
                    .presentationDetents([.large])
                    .presentationCornerRadius(TaleedSize.bottomSheetTopRadius)
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(TaleedColor.surfacePrimary)
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
            LoadingStateView()
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
                TaleedButton(title: referralsLinkTitle, kind: .hyperlink, size: .medium) { showsReferrals = true }
                    .accessibilityIdentifier("referrals.yourReferrals")
            }
        case .gate:
            InlineAlert(kind: .warning, title: l10n.string(.referralsGateTitle), message: l10n.string(.referralsGateBody),
                        actionTitle: l10n.string(.referralsGateCta)) {
                router.push(.identityVerification)
            }
            .accessibilityIdentifier("referrals.gate")
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

    private var termsNote: some View {
        Text(ReferralsCopy.termsNote(l10n.string(.referralsTermsNote), termsURL: copy.program.termsURL,
                                     linkColor: TaleedColor.textPrimary))
            .taleedFont(TaleedFont.bodySmall)
            .foregroundStyle(TaleedColor.textSecondary)
            .tint(TaleedColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                router.openInBrowser(url)
                return .handled
            })
            .accessibilityIdentifier("referrals.terms")
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

/// "Copier le lien d’invitation" (mint CTA), "Lien copié !" with a check for 2.5 s after a copy.
struct CopyInviteButton: View {
    let isCopied: Bool
    let copy: () -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        TaleedButton(title: l10n.string(isCopied ? .referralsCopied : .referralsCopyCta), kind: .secondary, size: .large,
                     leadingIcon: isCopied ? .check : .link, isFullWidth: true, action: copy)
            .accessibilityIdentifier("referrals.copy")
    }
}

/// "Partager le lien": the system share sheet with `inviteUrl` (slice E).
struct ShareInviteButton: View {
    let url: URL
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        ShareLink(item: url) {
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

// MARK: - How it works

/// "Comment fonctionne le parrainage": the three steps (artwork beside the text, a phone layout of the
/// website's three columns), then "Bon à savoir" with the rest of `program`.
private struct ReferralStepsSection: View {
    let copy: ReferralsCopy
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            Text(l10n.string(.referralsHowTitle))
                .taleedFont(TaleedFont.headline.with(weight: .bold))
                .foregroundStyle(TaleedColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            ReferralStepRow(image: .referralStep1, title: l10n.string(.referralsStep1Title), text: l10n.string(.referralsStep1Body))
            ReferralStepRow(image: .referralStep2, title: l10n.string(.referralsStep2Title), text: copy.step2Body)
            ReferralStepRow(image: .referralStep3, title: l10n.string(.referralsStep3Title), text: copy.step3Body)
            rules
        }
        .padding(.top, TaleedSpacing.s8)
        .overlay(alignment: .top) {
            Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1).offset(y: -TaleedSpacing.s16)
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            Text(l10n.string(.appReferralsRulesTitle))
                .taleedFont(TaleedFont.sectionTitle)
                .foregroundStyle(TaleedColor.brandDark)
                .accessibilityAddTraits(.isHeader)
            ForEach(copy.rules, id: \.self) { rule in
                HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8) {
                    Circle().fill(TaleedColor.brandPrimary).frame(width: 5, height: 5).accessibilityHidden(true)
                    Text(rule)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(TaleedSpacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaleedColor.brandSoft, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("referrals.rules")
    }
}

private struct ReferralStepRow: View {
    let image: TaleedImage
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: TaleedSpacing.s16) {
            Image(taleed: image)
                .resizable()
                .scaledToFit()
                .padding(TaleedSpacing.s4)
                .frame(width: 96, height: 96)
                .background(TaleedColor.surfaceGrouped, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                Text(title)
                    .taleedFont(TaleedFont.bodyLarge.with(weight: .semibold))
                    .foregroundStyle(TaleedColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(text)
                    .taleedFont(TaleedFont.bodyRegular)
                    .lineSpacing(3)
                    .foregroundStyle(TaleedColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
