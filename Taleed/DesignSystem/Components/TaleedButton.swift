import SwiftUI

/// Button types (design-system §2.1). Main CTAs in the wireframes are `secondary` (mint).
enum TaleedButtonKind: String, CaseIterable, Sendable {
    /// Blue, high emphasis. Sheet "Apply" and secondary flows (decision D-10).
    case primary
    /// Mint, the commerce CTA ("Publish listing", "Buy now").
    case secondary
    /// Soft blue companion ("Make an offer", "Message seller").
    case tertiary
    /// Text link.
    case hyperlink
    /// Destructive.
    case danger
}

enum TaleedButtonSize: String, CaseIterable, Sendable {
    case small, medium, large

    var height: CGFloat {
        switch self {
        case .small: TaleedSize.Button.Small.height
        case .medium: TaleedSize.Button.Medium.height
        case .large: TaleedSize.Button.Large.height
        }
    }

    var paddingX: CGFloat {
        switch self {
        case .small: TaleedSize.Button.Small.paddingX
        case .medium: TaleedSize.Button.Medium.paddingX
        case .large: TaleedSize.Button.Large.paddingX
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: TaleedSize.Button.Small.iconSize
        case .medium: TaleedSize.Button.Medium.iconSize
        case .large: TaleedSize.Button.Large.iconSize
        }
    }

    var iconOnlySize: CGFloat {
        switch self {
        case .small: TaleedSize.Button.Small.iconOnlySize
        case .medium: TaleedSize.Button.Medium.iconOnlySize
        case .large: TaleedSize.Button.Large.iconOnlySize
        }
    }

    var iconOnlyIconSize: CGFloat {
        switch self {
        case .small: TaleedSize.Button.Small.iconOnlyIconSize
        case .medium: TaleedSize.Button.Medium.iconOnlyIconSize
        case .large: TaleedSize.Button.Large.iconOnlyIconSize
        }
    }

    var hyperlinkHeight: CGFloat {
        self == .small ? TaleedSize.Button.Hyperlink.heightSmall : TaleedSize.Button.Hyperlink.heightMediumLarge
    }

    var textStyle: TaleedTextStyle {
        switch self {
        case .small: TaleedFont.buttonSmall
        case .medium: TaleedFont.buttonMedium
        case .large: TaleedFont.buttonLarge
        }
    }
}

/// The three drawn states. Loading is a separate flag that keeps the default colours.
enum TaleedButtonState: String, CaseIterable, Sendable {
    case normal, pressed, disabled
}

/// Fill, border and content colours of a button type in a state (design-system §2.1 table).
struct TaleedButtonColors: Equatable {
    let fill: Color?
    let border: Color?
    let content: Color

    // The table has one row per type; splitting it would make it harder to check against the spec.
    // swiftlint:disable:next cyclomatic_complexity
    static func of(_ kind: TaleedButtonKind, _ state: TaleedButtonState) -> TaleedButtonColors {
        typealias Palette = TaleedColor
        switch (kind, state) {
        case (.primary, .normal): return .init(fill: Palette.blue500, border: Palette.blue600, content: Palette.blue50)
        case (.primary, .pressed): return .init(fill: Palette.blue600, border: Palette.blue600, content: Palette.blue50)
        case (.primary, .disabled): return .init(fill: Palette.blue200, border: Palette.blue200, content: Palette.blue50)
        case (.secondary, .normal): return .init(fill: Palette.mint400, border: Palette.mint500, content: Palette.mint900)
        case (.secondary, .pressed): return .init(fill: Palette.mint500, border: Palette.mint500, content: Palette.mint900)
        case (.secondary, .disabled): return .init(fill: Palette.mint100, border: Palette.mint200, content: Palette.navy300)
        case (.tertiary, .normal): return .init(fill: Palette.blue50, border: Palette.blue100, content: Palette.blue600)
        case (.tertiary, .pressed): return .init(fill: Palette.blue100, border: Palette.blue100, content: Palette.blue600)
        case (.tertiary, .disabled): return .init(fill: Palette.blue50, border: Palette.blue100, content: Palette.blue200)
        case (.hyperlink, .normal): return .init(fill: nil, border: nil, content: Palette.blue500)
        case (.hyperlink, .pressed): return .init(fill: nil, border: nil, content: Palette.blue600)
        case (.hyperlink, .disabled): return .init(fill: nil, border: nil, content: Palette.blue200)
        case (.danger, .normal): return .init(fill: Palette.feedbackError, border: Palette.feedbackError, content: Palette.textInverse)
        case (.danger, .pressed): return .init(fill: Palette.dangerPressed, border: Palette.dangerPressed, content: Palette.textInverse)
        case (.danger, .disabled): return .init(fill: Palette.dangerDisabled, border: Palette.dangerDisabled, content: Palette.navy400)
        }
    }
}

/// The button style behind `TaleedButton` and `TaleedIconOnlyButton`. Use it on any `Button` whose
/// label is the design-system content.
struct TaleedButtonStyle: ButtonStyle {
    var kind: TaleedButtonKind = .primary
    var size: TaleedButtonSize = .large
    var isIconOnly = false
    var isFullWidth = false
    var minWidth: CGFloat?
    /// Draws a state regardless of the finger, for the design-system gallery.
    var forcedState: TaleedButtonState?

    func makeBody(configuration: Configuration) -> some View {
        TaleedButtonChrome(
            kind: kind, size: size, isIconOnly: isIconOnly, isFullWidth: isFullWidth, minWidth: minWidth,
            isPressed: configuration.isPressed, forcedState: forcedState
        ) {
            configuration.label
        }
    }
}

/// The container drawn around a button's content: fill, border, radius, height and padding.
struct TaleedButtonChrome<Content: View>: View {
    let kind: TaleedButtonKind
    let size: TaleedButtonSize
    var isIconOnly = false
    var isFullWidth = false
    var minWidth: CGFloat?
    var isPressed = false
    var forcedState: TaleedButtonState?
    @ViewBuilder let content: Content
    @Environment(\.isEnabled) private var isEnabled

    private var state: TaleedButtonState {
        forcedState ?? (!isEnabled ? .disabled : isPressed ? .pressed : .normal)
    }

    var body: some View {
        let colors = TaleedButtonColors.of(kind, state)
        let shape = RoundedRectangle(cornerRadius: TaleedSize.Button.radius, style: .continuous)
        content
            .foregroundStyle(colors.content)
            .padding(.horizontal, isIconOnly || kind == .hyperlink ? 0 : size.paddingX)
            .padding(.vertical, isIconOnly ? 0 : 4)
            .frame(
                minWidth: isIconOnly ? size.iconOnlySize : minWidth,
                maxWidth: isFullWidth ? .infinity : nil,
                minHeight: isIconOnly ? size.iconOnlySize : (kind == .hyperlink ? size.hyperlinkHeight : size.height)
            )
            .background {
                if let fill = colors.fill { shape.fill(fill) }
            }
            .overlay {
                if let border = colors.border { shape.strokeBorder(border, lineWidth: TaleedSize.Button.borderWidth) }
            }
            .contentShape(shape)
            .minimumHitArea()
    }
}

/// A text button with optional leading and trailing icons and a loading state.
struct TaleedButton: View {
    let title: String
    var kind: TaleedButtonKind = .primary
    var size: TaleedButtonSize = .large
    var leadingIcon: TaleedIcon?
    var trailingIcon: TaleedIcon?
    /// Shows a spinner instead of the label and ignores taps; the colours stay the default ones.
    var isLoading = false
    var isFullWidth = false
    var minWidth: CGFloat?
    /// Overrides the colour of the leading icon (Login "Continue with email" uses `blue/600`).
    var leadingIconColor: Color?
    var forcedState: TaleedButtonState?
    let action: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            HStack(spacing: TaleedSize.Button.gap) {
                if let leadingIcon {
                    TaleedIconView(leadingIcon, size: size.iconSize, color: leadingIconColor)
                }
                Text(title)
                    .taleedFont(size.textStyle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let trailingIcon {
                    TaleedIconView(trailingIcon, size: size.iconSize, color: nil)
                }
            }
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading {
                    ProgressView()
                        .tint(TaleedButtonColors.of(kind, .normal).content)
                }
            }
        }
        // Loading keeps the Default colours even inside a disabled container.
        .buttonStyle(TaleedButtonStyle(kind: kind, size: size, isFullWidth: isFullWidth, minWidth: minWidth,
                                       forcedState: forcedState ?? (isLoading ? .normal : nil)))
        .allowsHitTesting(!isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? DesignSystemStrings.string(.commonLoading, locale: locale) : "")
    }
}

/// An icon-only button (32, 40 or 48 box; 44 pt hit area). Needs an accessibility label.
struct TaleedIconOnlyButton: View {
    let icon: TaleedIcon
    let accessibilityLabel: String
    var kind: TaleedButtonKind = .primary
    var size: TaleedButtonSize = .large
    var forcedState: TaleedButtonState?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(taleed: icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size.iconOnlyIconSize, height: size.iconOnlyIconSize)
                .flipsForRightToLeftLayoutDirection(icon.isDirectional)
        }
        .buttonStyle(TaleedButtonStyle(kind: kind, size: size, isIconOnly: true, forcedState: forcedState))
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The outlined button that the seller card ("View profile"), the empty state ("Clear filters") and
/// the confirmation modal ("Cancel", "Delete") draw outside the Button component (design-system §8.10):
/// `radius.m`, 13/600 or 15/600 label. Pressed changes only the fill and border, never the label
/// contrast: white → `surfaceGrouped`, danger → `lit.dangerPressed`.
struct TaleedOutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 40
    var paddingX: CGFloat = TaleedSpacing.s16
    var textStyle = TaleedOutlineButtonStyle.label13
    var fill = TaleedColor.surfacePrimary
    var border = TaleedColor.borderSubtle
    var foreground = TaleedColor.textPrimary
    /// Fill and border while the finger is down. Nil derives them from the button's own colours:
    /// a white button turns `surfaceGrouped`, any other keeps its fill (never a lighter one under a
    /// light label).
    var pressedFill: Color?
    var pressedBorder: Color?
    var isFullWidth = false
    /// Draws the pressed look regardless of the finger, for the design-system gallery.
    var forcesPressed = false

    static let label13 = TaleedTextStyle(size: 13, weight: .semibold, lineHeight: nil, letterSpacing: 0, relativeTo: .footnote)
    static let label15 = TaleedTextStyle(size: 15, weight: .semibold, lineHeight: nil, letterSpacing: 0, relativeTo: .subheadline)

    /// The modal's destructive action: `feedback/error` fill and border, white label; pressed
    /// `lit.dangerPressed` #B42318 like the Danger button (§2.1).
    static func danger(height: CGFloat = 40, isFullWidth: Bool = false, forcesPressed: Bool = false) -> TaleedOutlineButtonStyle {
        TaleedOutlineButtonStyle(height: height, fill: TaleedColor.feedbackError, border: TaleedColor.feedbackError,
                                 foreground: TaleedColor.textInverse, pressedFill: TaleedColor.dangerPressed,
                                 pressedBorder: TaleedColor.dangerPressed, isFullWidth: isFullWidth, forcesPressed: forcesPressed)
    }

    private var resolvedPressedFill: Color {
        pressedFill ?? (fill == TaleedColor.surfacePrimary ? TaleedColor.surfaceGrouped : fill)
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: TaleedRadius.m, style: .continuous)
        let isPressed = configuration.isPressed || forcesPressed
        configuration.label
            .taleedFont(textStyle)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, paddingX)
            .padding(.vertical, 4)
            .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: height)
            .background(shape.fill(isPressed ? resolvedPressedFill : fill))
            .overlay(shape.strokeBorder(isPressed ? pressedBorder ?? border : border, lineWidth: 1))
            .contentShape(shape)
            .minimumHitArea()
    }
}

#Preview("Buttons") {
    VStack(spacing: 12) {
        ForEach(TaleedButtonKind.allCases, id: \.self) { kind in
            TaleedButton(title: "Publish listing", kind: kind, leadingIcon: .plus) {}
        }
        TaleedButton(title: "Buy now", kind: .secondary, isLoading: true, isFullWidth: true) {}
        TaleedIconOnlyButton(icon: .caretLeft, accessibilityLabel: "Back", kind: .hyperlink, size: .medium) {}
    }
    .padding()
}
