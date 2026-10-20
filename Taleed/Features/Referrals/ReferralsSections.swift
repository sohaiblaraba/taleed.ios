import SwiftUI

// MARK: - How it works

/// "Comment fonctionne le parrainage": the three steps (artwork beside the text, a phone layout of the
/// website's three columns; above it at accessibility sizes), then "Bon à savoir" with the rest of
/// `program`. The hero card's border already separates it from the card: no rule above, more space.
struct ReferralStepsSection: View {
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
        .padding(.top, TaleedSpacing.s16)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: TaleedSpacing.s12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: TaleedSpacing.s16))
        layout {
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

// MARK: - Loading

/// The hero card's shape while the program loads (design-system §3.6, six placeholders): the artwork,
/// the eyebrow, the title, two lines of text and the main button.
struct ReferralHeroSkeleton: View {
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonBlock(height: 200, radius: TaleedRadius.m)
                .padding([.top, .horizontal], TaleedSpacing.s16)
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                SkeletonBlock(width: 160, height: 12)
                SkeletonBlock(height: 22)
                SkeletonBlock(height: 14, color: TaleedColor.surfaceSubtle)
                SkeletonBlock(width: 220, height: 14, color: TaleedColor.surfaceSubtle)
                SkeletonBlock(height: TaleedSize.buttonLargeHeight, radius: TaleedSize.buttonRadius)
                    .padding(.top, TaleedSpacing.s8)
            }
            .padding(TaleedSpacing.s16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaleedColor.surfacePrimary, in: RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous).strokeBorder(TaleedColor.borderSubtle))
        .skeletonPulse()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.string(.commonLoading))
        .accessibilityIdentifier("referrals.loading")
    }
}
