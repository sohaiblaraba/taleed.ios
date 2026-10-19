import SwiftUI

/// A trailing app-bar action: an icon with an accessibility label. At most two per bar.
struct AppBarAction: Identifiable {
    let icon: TaleedIcon
    let accessibilityLabel: String
    /// Draws the 40 pt `blue/50` circle behind the icon (Item Detail trust icon).
    var isCircled = false
    var color: Color = TaleedColor.blue600
    /// Nil draws a non-interactive indicator (the wireframes' trust shield).
    var action: (() -> Void)?

    var id: String { icon.rawValue }
}

/// The 56 pt app-bar frame: padding 16, white, optional 1 pt bottom border (decision D-1).
private struct AppBarContainer<Content: View>: View {
    var showsDivider: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, TaleedSize.AppBar.paddingX)
            .frame(maxWidth: .infinity, minHeight: TaleedSize.AppBar.height)
            .background(TaleedColor.surfacePrimary)
            .overlay(alignment: .bottom) {
                if showsDivider { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
            }
    }
}

/// Brand app bar (Home, Sell, top-level tabs): wordmark, then notifications and the member's avatar.
struct BrandAppBar: View {
    var showsDivider = false
    var onNotifications: (() -> Void)?
    /// The member's initials; nil hides the avatar (signed out).
    var avatarInitials: String?
    var avatarURL: URL?
    var avatarAccessibilityLabel: String = ""
    var onAvatar: (() -> Void)?
    @Environment(\.locale) private var locale

    var body: some View {
        AppBarContainer(showsDivider: showsDivider) {
            HStack(spacing: TaleedSpacing.s12) {
                Image(taleed: .wordmark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 95, height: 24)
                    .accessibilityLabel(DesignSystemStrings.string(.appName, locale: locale))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let onNotifications {
                    Button(action: onNotifications) {
                        TaleedIconView(.bell, size: 24, color: TaleedColor.textPrimary)
                            .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DesignSystemStrings.string(.a11yNotifications, locale: locale))
                }
                if let avatarInitials {
                    let avatar = TaleedAvatar(initials: avatarInitials, size: 36, imageURL: avatarURL, style: .wireframe)
                    if let onAvatar {
                        Button(action: onAvatar) { avatar.minimumHitArea() }
                            .buttonStyle(.plain)
                            .accessibilityLabel(avatarAccessibilityLabel)
                    } else {
                        avatar
                    }
                }
            }
        }
    }
}

/// Back + centred title + up to two actions (Item Detail, Checkout, pushed screens).
struct TaleedAppBar: View {
    let title: String
    var showsDivider = true
    /// Nil hides the back button (a root screen).
    var onBack: (() -> Void)?
    var backAccessibilityLabel: String = ""
    var actions: [AppBarAction] = []

    private let sideBox: CGFloat = 40

    var body: some View {
        AppBarContainer(showsDivider: showsDivider) {
            ZStack {
                Text(title)
                    .taleedFont(TaleedFont.appBarTitle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, sideWidth + TaleedSpacing.s12)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        if let onBack {
                            TaleedIconOnlyButton(icon: .caretLeft, accessibilityLabel: backAccessibilityLabel,
                                                 kind: .hyperlink, size: .medium, action: onBack)
                        }
                    }
                    .frame(width: sideWidth, alignment: .leading)
                    Spacer(minLength: 0)
                    HStack(spacing: TaleedSpacing.s4) {
                        ForEach(actions.prefix(2)) { AppBarActionView(action: $0, box: sideBox) }
                    }
                    .frame(width: sideWidth, alignment: .trailing)
                }
            }
        }
    }

    /// Both sides take the width of the wider one, so the title stays centred.
    private var sideWidth: CGFloat {
        let trailing = CGFloat(min(actions.count, 2)) * sideBox + (actions.count > 1 ? TaleedSpacing.s4 : 0)
        return max(onBack == nil ? 0 : sideBox, trailing)
    }
}

private struct AppBarActionView: View {
    let action: AppBarAction
    let box: CGFloat

    var body: some View {
        let icon = TaleedIconView(action.icon, size: 20, color: action.color)
            .frame(width: box, height: box)
            .background {
                if action.isCircled { Circle().fill(TaleedColor.blue50) }
            }
        if let handler = action.action {
            Button(action: handler) { icon.minimumHitArea() }
                .buttonStyle(.plain)
                .accessibilityLabel(action.accessibilityLabel)
        } else {
            icon
                .accessibilityElement()
                .accessibilityLabel(action.accessibilityLabel)
        }
    }
}

/// Search app bar: magnifying glass, the query field and a clear button.
struct SearchAppBar: View {
    @Binding var text: String
    var placeholder: String
    var showsDivider = true
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool
    @Environment(\.locale) private var locale

    private static let fieldStyle = TaleedTextStyle(size: 15, weight: .regular, lineHeight: nil, letterSpacing: 0,
                                                    relativeTo: .subheadline)

    var body: some View {
        AppBarContainer(showsDivider: showsDivider) {
            HStack(spacing: TaleedSpacing.s12) {
                TaleedIconView(.magnifyingGlass, size: 20, color: TaleedColor.textSecondary)
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(TaleedColor.textSecondary))
                    .taleedFont(Self.fieldStyle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .tint(TaleedColor.brandPrimary)
                    .submitLabel(.search)
                    .focused($isFocused)
                    .onSubmit(onSubmit)
                    .accessibilityLabel(placeholder)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        TaleedIconView(.x, size: 20, color: TaleedColor.textPrimary)
                            .frame(width: 40, height: 40)
                            .minimumHitArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DesignSystemStrings.string(.a11yClearText, locale: locale))
                }
            }
        }
    }
}

/// Page heading under the app bar (Sell, Checkout): eyebrow and screen title, then a divider.
struct PageHeading: View {
    var eyebrow: String?
    let title: String
    var showsDivider = true

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
            if let eyebrow { Eyebrow(text: eyebrow) }
            Text(title)
                .taleedFont(TaleedFont.screenTitle)
                .foregroundStyle(TaleedColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, TaleedLayout.PageHeadingPadding.top)
        .padding(.horizontal, TaleedLayout.PageHeadingPadding.x)
        .padding(.bottom, TaleedLayout.PageHeadingPadding.bottom)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
        }
    }
}

/// Uppercase kicker in `brand/primary`, 11/600 +5 % ("SELL", "DELIVERY METHOD").
struct Eyebrow: View {
    let text: String
    @Environment(\.locale) private var locale

    var body: some View {
        Text(text.uppercased(with: locale))
            .taleedFont(TaleedFont.eyebrow)
            .foregroundStyle(TaleedColor.brandPrimary)
            .accessibilityLabel(text)
    }
}

/// Section title (Item Detail "Description", "Seller"): 15/700.
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .taleedFont(TaleedFont.sectionTitle)
            .foregroundStyle(TaleedColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The 8 pt `navy/50` band between detail sections.
struct SectionBand: View {
    var body: some View {
        Rectangle().fill(TaleedColor.navy50).frame(height: 8).accessibilityHidden(true)
    }
}

/// A settings-style list row (decision D-12, screens Figma does not draw): 14 pt title, optional
/// value, check or chevron, 1 pt bottom border, 52 pt high. Item Detail's spec rows are `SpecRow`.
struct TaleedListRow: View {
    let title: String
    var value: String?
    var leadingIcon: TaleedIcon?
    var titleColor: Color = TaleedColor.textPrimary
    var showsChevron = true
    var showsDivider = true
    var isSelected = false
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: TaleedSpacing.s12) {
            if let leadingIcon { TaleedIconView(leadingIcon, size: 20, color: TaleedColor.textSecondary) }
            Text(title)
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(titleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondary)
            }
            if isSelected { TaleedIconView(.check, size: 20, color: TaleedColor.brandPrimary) }
            if showsChevron, action != nil { TaleedIconView(.caretRight, size: 18, color: TaleedColor.textSecondary) }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, TaleedSpacing.s16)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if showsDivider { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
        }
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { content }
                .buttonStyle(ListRowButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

private struct ListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? TaleedColor.surfaceGrouped : TaleedColor.surfacePrimary)
    }
}
