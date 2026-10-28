import SwiftUI

/// A trailing app-bar action: an icon with an accessibility label. At most two per bar.
struct AppBarAction: Identifiable {
    let icon: TaleedIcon
    let accessibilityLabel: String
    /// Draws the 40 pt `blue/50` circle behind the icon (Item Detail trust icon).
    var isCircled = false
    var color: Color = TaleedColor.brandEmphasis
    /// Nil draws a non-interactive indicator.
    var action: (() -> Void)?
    /// An overflow menu instead of `action` (screens.md §2 G4: Report listing): `TaleedOverflowMenu`.
    var menu: [AppBarMenuItem] = []
    /// For UI tests and screenshot scripts.
    var accessibilityIdentifier: String?

    var id: String { icon.rawValue }
}

/// An entry of an app-bar overflow menu.
struct AppBarMenuItem: Identifiable {
    let title: String
    /// Drawn before the title, in its colour (a flag-like `warning` for Report, as the listing's
    /// "Signaler" link).
    var icon: TaleedIcon?
    /// Only for an action that removes or cuts something off (Block, Delete): `feedback/error`.
    var isDestructive = false
    /// For UI tests and screenshot scripts.
    var accessibilityIdentifier: String?
    let action: () -> Void

    var id: String { title }
}

/// The 56 pt app-bar frame: padding 16, white, optional 1 pt bottom border (decision D-1).
private struct AppBarContainer<Content: View>: View {
    var showsDivider: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, TaleedSize.appBarPaddingX)
            .frame(maxWidth: .infinity, minHeight: TaleedSize.appBarHeight)
            .background(TaleedColor.surfacePrimary)
            .overlay(alignment: .bottom) {
                if showsDivider { Rectangle().fill(TaleedColor.borderSubtle).frame(height: 1) }
            }
    }
}

/// Brand app bar (design-system §5.1, Home and Sell): wordmark at the start; the notifications bell
/// and the member's avatar (36, wireframe style) at the end. `onNotifications` nil hides the bell;
/// `avatarInitials` nil hides the avatar (signed out).
struct BrandAppBar: View {
    var showsDivider = false
    var onNotifications: (() -> Void)?
    /// Unread notifications on the bell (hidden at 0, "9+" above 9).
    var notificationsBadge = 0
    var notificationsBadgeAccessibilityLabel: String?
    var avatarInitials: String?
    var avatarURL: URL?
    /// Defaults to "Profile" (`tab_profile`).
    var avatarAccessibilityLabel: String?
    var onAvatar: (() -> Void)?
    /// Signed out (no `avatarInitials`): a neutral avatar (the `user` icon in a 36 pt `blue/100` circle)
    /// that opens sign-in, so the bar keeps Figma's shape. Nil shows nothing.
    var onSignIn: (() -> Void)?
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
                            .overlay(alignment: .topTrailing) {
                                if notificationsBadge > 0 {
                                    CountBadge(count: notificationsBadge,
                                               accessibilityLabel: notificationsBadgeAccessibilityLabel ?? "",
                                               maxCount: 9, size: .small)
                                        .offset(x: 8, y: -6)
                                }
                            }
                            .frame(width: TaleedSize.touchTargetMin, height: TaleedSize.touchTargetMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DesignSystemStrings.string(.commonNotifications, locale: locale))
                    .accessibilityValue(notificationsBadge > 0 ? notificationsBadgeAccessibilityLabel ?? "" : "")
                }
                if let avatarInitials {
                    let avatar = TaleedAvatar(initials: avatarInitials, size: 36, imageURL: avatarURL, style: .wireframe)
                    if let onAvatar {
                        Button(action: onAvatar) { avatar.minimumHitArea() }
                            .buttonStyle(.plain)
                            .accessibilityLabel(avatarAccessibilityLabel ?? DesignSystemStrings.string(.tabProfile, locale: locale))
                    } else {
                        avatar
                    }
                } else if let onSignIn {
                    Button(action: onSignIn) {
                        TaleedIconView(.user, size: 20, color: TaleedColor.brandEmphasis)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(TaleedColor.brandTintStrong))
                            .minimumHitArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DesignSystemStrings.string(.authSignIn, locale: locale))
                }
            }
        }
    }
}

/// App bar with back, a centred 16/700 title and up to two actions (design-system §5.1: Item Detail,
/// Checkout, pushed screens and the tab roots Figma does not draw, decision D-12). The title stays
/// centred because both sides reserve the same width. `onBack` nil hides the back button (tab roots).
/// Android: `TaleedTopAppBar`.
struct TaleedTopAppBar: View {
    let title: String
    var showsDivider = true
    var onBack: (() -> Void)?
    /// Defaults to "Back" (`common_back`).
    var backAccessibilityLabel: String?
    var actions: [AppBarAction] = []
    /// False hides the title while the page's own large heading says the same (it fades in once the
    /// heading scrolled away).
    var showsTitle = true
    @Environment(\.locale) private var locale

    private let sideBox: CGFloat = 40

    var body: some View {
        AppBarContainer(showsDivider: showsDivider) {
            ZStack {
                Text(title)
                    .taleedFont(TaleedFont.appBarTitle)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .lineLimit(1)
                    // Capped like a native navigation title; the large content viewer shows it bigger.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .accessibilityShowsLargeContentViewer()
                    .padding(.horizontal, sideWidth + TaleedSpacing.s12)
                    .accessibilityAddTraits(.isHeader)
                    .opacity(showsTitle ? 1 : 0)
                    .accessibilityHidden(!showsTitle)
                    .animation(.easeInOut(duration: TaleedMotion.transitionMin), value: showsTitle)
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        if let onBack {
                            TaleedIconOnlyButton(icon: .caretLeft,
                                                 accessibilityLabel: backAccessibilityLabel
                                                     ?? DesignSystemStrings.string(.commonBack, locale: locale),
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
                if action.isCircled { Circle().fill(TaleedColor.brandTint) }
            }
        if !action.menu.isEmpty {
            TaleedOverflowMenu(items: action.menu, accessibilityLabel: action.accessibilityLabel) {
                icon.minimumHitArea()
            }
        } else if let handler = action.action {
            Button(action: handler) { icon.minimumHitArea() }
                .buttonStyle(.plain)
                .accessibilityLabel(action.accessibilityLabel)
                .accessibilityIdentifier(action.accessibilityIdentifier ?? "")
        } else {
            icon
                .accessibilityElement()
                .accessibilityLabel(action.accessibilityLabel)
        }
    }
}

/// Search app bar: magnifying glass, the query field and a clear button. With `onCamera`, an empty
/// field ends with the photo-search button instead (the website's search bar; Phosphor has no camera
/// glyph in the design system, so it uses the system's).
struct SearchAppBar: View {
    @Binding var text: String
    var placeholder: String
    var showsDivider = true
    var onSubmit: () -> Void = {}
    var onCamera: (() -> Void)?
    var cameraAccessibilityLabel: String?
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
                    .accessibilityLabel(DesignSystemStrings.string(.commonClear, locale: locale))
                } else if let onCamera {
                    Button(action: onCamera) {
                        Image(systemName: "camera")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(TaleedColor.textSecondary)
                            .frame(width: 40, height: 40)
                            .minimumHitArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cameraAccessibilityLabel ?? "")
                    .accessibilityIdentifier("search.camera")
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
                // Stops growing at Accessibility 2, so the form under it starts higher on screen.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, TaleedLayout.pageHeadingPaddingTop)
        .padding(.horizontal, TaleedLayout.pageHeadingPaddingX)
        .padding(.bottom, TaleedLayout.pageHeadingPaddingBottom)
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
            // A small uppercase header: it stops growing at Accessibility 1 rather than wrap over huge lines.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
        Rectangle().fill(TaleedColor.sectionBand).frame(height: 8).accessibilityHidden(true)
    }
}
