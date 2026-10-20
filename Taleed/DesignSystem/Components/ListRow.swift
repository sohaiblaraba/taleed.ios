import SwiftUI

/// A settings-style row (decision D-12, screens Figma does not draw; built from Item Detail's spec
/// rows), the same as Android's `ListRow`: flat and full width, at least 56 high, padding 12 / 16,
/// optional leading icon, Body/Large label, optional trailing text (or a small badge, or a quiet
/// placeholder while it loads), a check when selected and a caret when it navigates (an arrow out for
/// a row that leaves the app), then a 1 pt divider inset 16 from the start. Item Detail's spec rows
/// are `SpecRow`.
///
/// The label never breaks inside a word (it steps down in size instead), and at the accessibility text
/// sizes the trailing value moves under the label, so the label keeps the row's width.
struct ListRow: View {
    let label: String
    var leadingIcon: TaleedIcon?
    var trailingText: String?
    /// A status after the label ("Vérifié"), drawn as the compact badge.
    var trailingBadge: TaleedBadge?
    /// A placeholder bar where the trailing value will show (the wallet's figure while it loads).
    var isTrailingLoading = false
    /// An unread count before the chevron (hidden at 0, "9+" above 9), with its VoiceOver text.
    var badgeCount = 0
    var badgeAccessibilityLabel: String?
    var showsChevron = false
    /// An arrow out (`arrow-up-right`) in place of the chevron: the row opens Mail, the phone or
    /// another app rather than a screen of the app.
    var opensOutside = false
    var showsDivider = true
    var labelColor: Color = TaleedColor.textPrimary
    var isSelected = false
    /// One line that scales down instead of wrapping, for a label that must not break inside a word
    /// (an email address, a phone number).
    var keepsLabelOnOneLine = false
    var action: (() -> Void)?
    /// The leading icon grows with the text (up to 36 pt), so it does not look tiny beside large text.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasTrailingValue: Bool { trailingText != nil || trailingBadge != nil || isTrailingLoading }

    var body: some View {
        let stacksValue = dynamicTypeSize.isAccessibilitySize && hasTrailingValue
        let content = HStack(spacing: TaleedSpacing.s12) {
            if let leadingIcon { TaleedIconView(leadingIcon, size: min(iconSize, 36), color: TaleedColor.textSecondary) }
            if stacksValue {
                VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                    labelText
                    trailingValue
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                labelText.frame(maxWidth: .infinity, alignment: .leading)
                trailingValue
            }
            if badgeCount > 0 {
                CountBadge(count: badgeCount, accessibilityLabel: badgeAccessibilityLabel ?? "", maxCount: 9)
            }
            if isSelected { TaleedIconView(.check, size: 20, color: TaleedColor.brandPrimary) }
            if opensOutside {
                TaleedIconView(.arrowUpRight, size: 18, color: TaleedColor.textSecondary)
            } else if showsChevron {
                TaleedIconView(.caretRight, size: 18, color: TaleedColor.textSecondary)
            }
        }
        .padding(.vertical, TaleedSpacing.s12)
        .padding(.horizontal, TaleedLayout.screenMargin)
        .frame(maxWidth: .infinity, minHeight: 56)
        .contentShape(Rectangle())
        VStack(spacing: 0) {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(ListRowButtonStyle())
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                content.accessibilityElement(children: .combine)
            }
            if showsDivider {
                Rectangle()
                    .fill(TaleedColor.borderSubtle)
                    .frame(height: 1)
                    .padding(.leading, TaleedLayout.screenMargin)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var labelText: some View {
        if keepsLabelOnOneLine {
            Text(label)
                .taleedFont(TaleedFont.bodyLarge)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        } else {
            WordFittingText(text: label, style: TaleedFont.bodyLarge)
                .foregroundStyle(labelColor)
        }
    }

    @ViewBuilder
    private var trailingValue: some View {
        if let trailingText {
            Text(trailingText)
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textSecondary)
        } else if let trailingBadge {
            trailingBadge
        } else if isTrailingLoading {
            SkeletonBlock(width: 64, height: 14)
                .skeletonPulse()
                .accessibilityHidden(true)
        }
    }
}

private struct ListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? TaleedColor.surfaceGrouped : TaleedColor.surfacePrimary)
    }
}
