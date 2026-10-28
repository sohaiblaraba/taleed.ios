import SwiftUI

/// Button types (design-system §2.1), the same as Android's `TaleedButtonType`. `secondary` (mint) is
/// the main commerce CTA in the wireframes and the default (decision D-10).
enum TaleedButtonKind: String, CaseIterable, Sendable {
    /// Blue, high emphasis. Sheet "Apply" and secondary flows (decision D-10).
    case primary
    /// Mint, the commerce CTA ("Publish listing", "Buy now").
    case secondary
    /// Soft blue companion ("Make an offer", "Message seller").
    case tertiary
    /// Text link.
    case hyperlink
    /// The Login override of Hyperlink ("Browse without signing in"): `blue/900` label with a 2 pt
    /// `blue/900` bottom border.
    case hyperlinkUnderlined
    /// Destructive.
    case danger
    /// The text link of a destructive step that needs no confirmation ("Annuler l'offre"): Hyperlink's
    /// shape with the `feedback/error` label, so it does not read like a positive action.
    case hyperlinkDanger
    /// Not in the Figma Button set: the white frame Figma draws for "View profile", "Clear filters"
    /// and the modal "Cancel" (§8.10): `radius.m`, Medium 13/600 padding 16, Large 15/600 padding 24.
    case outline
    /// The Login wireframe's override of Tertiary for "Continue with email": `mint/50` fill, `mint/100`
    /// border, `mint/900` label (pair it with a `blue/600` leading icon).
    case mintSoft

    var isHyperlink: Bool { self == .hyperlink || self == .hyperlinkUnderlined || self == .hyperlinkDanger }
}

enum TaleedButtonSize: String, CaseIterable, Sendable {
    case small, medium, large

    var height: CGFloat {
        switch self {
        case .small: TaleedSize.buttonSmallHeight
        case .medium: TaleedSize.buttonMediumHeight
        case .large: TaleedSize.buttonLargeHeight
        }
    }

    var paddingX: CGFloat {
        switch self {
        case .small: TaleedSize.buttonSmallPaddingX
        case .medium: TaleedSize.buttonMediumPaddingX
        case .large: TaleedSize.buttonLargePaddingX
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: TaleedSize.buttonSmallIconSize
        case .medium: TaleedSize.buttonMediumIconSize
        case .large: TaleedSize.buttonLargeIconSize
        }
    }

    var iconOnlySize: CGFloat {
        switch self {
        case .small: TaleedSize.buttonSmallIconOnlySize
        case .medium: TaleedSize.buttonMediumIconOnlySize
        case .large: TaleedSize.buttonLargeIconOnlySize
        }
    }

    var iconOnlyIconSize: CGFloat {
        switch self {
        case .small: TaleedSize.buttonSmallIconOnlyIconSize
        case .medium: TaleedSize.buttonMediumIconOnlyIconSize
        case .large: TaleedSize.buttonLargeIconOnlyIconSize
        }
    }

    var hyperlinkHeight: CGFloat {
        self == .small ? TaleedSize.buttonHyperlinkHeightSmall : TaleedSize.buttonHyperlinkHeightMediumLarge
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
        // swiftlint:disable line_length
        switch (kind, state) {
        case (.primary, .normal): return .init(fill: Palette.brandPrimary, border: Palette.primaryButtonBorder, content: Palette.primaryButtonContent)
        case (.primary, .pressed): return .init(fill: Palette.primaryButtonPressed, border: Palette.primaryButtonPressed, content: Palette.primaryButtonContent)
        case (.primary, .disabled): return .init(fill: Palette.primaryButtonDisabled, border: Palette.primaryButtonDisabled, content: Palette.primaryButtonDisabledContent)
        case (.secondary, .normal): return .init(fill: Palette.mint400, border: Palette.mint500, content: Palette.mint900)
        case (.secondary, .pressed): return .init(fill: Palette.mint500, border: Palette.mint500, content: Palette.mint900)
        case (.secondary, .disabled): return .init(fill: Palette.secondaryButtonDisabled, border: Palette.secondaryButtonDisabledBorder, content: Palette.secondaryButtonDisabledContent)
        case (.tertiary, .normal): return .init(fill: Palette.brandTint, border: Palette.brandTintBorder, content: Palette.brandEmphasis)
        case (.tertiary, .pressed): return .init(fill: Palette.brandTintStrong, border: Palette.brandTintBorder, content: Palette.brandEmphasis)
        case (.tertiary, .disabled): return .init(fill: Palette.brandTint, border: Palette.brandTintBorder, content: Palette.linkDisabled)
        case (.hyperlink, .normal): return .init(fill: nil, border: nil, content: Palette.brandPrimary)
        case (.hyperlink, .pressed): return .init(fill: nil, border: nil, content: Palette.linkPressed)
        case (.hyperlink, .disabled): return .init(fill: nil, border: nil, content: Palette.linkDisabled)
        case (.hyperlinkUnderlined, .normal): return .init(fill: nil, border: nil, content: Palette.linkStrong)
        case (.hyperlinkUnderlined, .pressed): return .init(fill: nil, border: nil, content: Palette.linkStrongPressed)
        case (.hyperlinkUnderlined, .disabled): return .init(fill: nil, border: nil, content: Palette.linkDisabled)
        case (.hyperlinkDanger, .normal): return .init(fill: nil, border: nil, content: Palette.feedbackError)
        case (.hyperlinkDanger, .pressed): return .init(fill: nil, border: nil, content: Palette.dangerPressed)
        case (.hyperlinkDanger, .disabled): return .init(fill: nil, border: nil, content: Palette.contentDisabled)
        case (.danger, .normal): return .init(fill: Palette.feedbackError, border: Palette.feedbackError, content: Palette.onFeedbackError)
        case (.danger, .pressed): return .init(fill: Palette.dangerPressed, border: Palette.dangerPressed, content: Palette.onFeedbackError)
        case (.danger, .disabled): return .init(fill: Palette.dangerDisabled, border: Palette.dangerDisabled, content: Palette.iconDisabled)
        // Pressed changes only the fill, never the label contrast.
        case (.outline, .normal): return .init(fill: Palette.surfacePrimary, border: Palette.borderSubtle, content: Palette.textPrimary)
        case (.outline, .pressed): return .init(fill: Palette.surfaceGrouped, border: Palette.borderSubtle, content: Palette.textPrimary)
        case (.outline, .disabled): return .init(fill: Palette.surfacePrimary, border: Palette.borderSubtle, content: Palette.contentDisabled)
        case (.mintSoft, .normal): return .init(fill: Palette.mintTint, border: Palette.mintTintBorder, content: Palette.mintOnTint)
        case (.mintSoft, .pressed): return .init(fill: Palette.mintTintBorder, border: Palette.mintTintBorder, content: Palette.mintOnTint)
        case (.mintSoft, .disabled): return .init(fill: Palette.mintTint, border: Palette.mintTintBorder, content: Palette.contentDisabled)
        }
        // swiftlint:enable line_length
    }
}

/// Radius, horizontal padding and label style of a button type at a size.
struct TaleedButtonMetrics: Equatable {
    let radius: CGFloat
    let paddingX: CGFloat
    let textStyle: TaleedTextStyle

    /// The outline frames' labels: 13/600 and 15/600 with the natural line height.
    static let outlineMedium = TaleedTextStyle(size: 13, weight: .semibold, lineHeight: nil, letterSpacing: 0,
                                               relativeTo: .footnote)
    static let outlineLarge = TaleedTextStyle(size: 15, weight: .semibold, lineHeight: nil, letterSpacing: 0,
                                              relativeTo: .subheadline)

    static func of(_ kind: TaleedButtonKind, _ size: TaleedButtonSize) -> TaleedButtonMetrics {
        if kind == .outline {
            switch size {
            case .small: return .init(radius: TaleedRadius.m, paddingX: TaleedSize.buttonSmallPaddingX, textStyle: size.textStyle)
            case .medium: return .init(radius: TaleedRadius.m, paddingX: TaleedSpacing.s16, textStyle: outlineMedium)
            case .large: return .init(radius: TaleedRadius.m, paddingX: TaleedSpacing.s24, textStyle: outlineLarge)
            }
        }
        return .init(radius: TaleedSize.buttonRadius, paddingX: kind.isHyperlink ? TaleedSize.buttonHyperlinkPaddingX : size.paddingX,
                     textStyle: size.textStyle)
    }

    /// The confirmation modal's two actions (§5.4), outline or danger: 40 high, padding 16, 13/600,
    /// `radius.m` (Android's `ModalActionButton`).
    static let modalAction = TaleedButtonMetrics(radius: TaleedRadius.m, paddingX: TaleedSpacing.s16, textStyle: outlineMedium)
}

/// The button style behind `TaleedButton` and `TaleedIconOnlyButton`. Use it on any `Button` whose
/// label is the design-system content.
struct TaleedButtonStyle: ButtonStyle {
    var kind: TaleedButtonKind = .secondary
    var size: TaleedButtonSize = .large
    var isIconOnly = false
    /// An icon-only box other than the size's (the search row's 44 pt filter button, as tall as the field).
    var iconOnlyBoxSize: CGFloat?
    var isFullWidth = false
    var minWidth: CGFloat?
    var metrics: TaleedButtonMetrics?
    /// Draws a state regardless of the finger, for the design-system gallery.
    var forcedState: TaleedButtonState?

    func makeBody(configuration: Configuration) -> some View {
        TaleedButtonChrome(
            kind: kind, size: size, isIconOnly: isIconOnly, iconOnlyBoxSize: iconOnlyBoxSize, isFullWidth: isFullWidth,
            minWidth: minWidth, metrics: metrics ?? .of(kind, size), isPressed: configuration.isPressed,
            forcedState: forcedState
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
    var iconOnlyBoxSize: CGFloat?
    var isFullWidth = false
    var minWidth: CGFloat?
    var metrics: TaleedButtonMetrics
    var isPressed = false
    var forcedState: TaleedButtonState?
    @ViewBuilder let content: Content
    @Environment(\.isEnabled) private var isEnabled

    private var state: TaleedButtonState {
        forcedState ?? (!isEnabled ? .disabled : isPressed ? .pressed : .normal)
    }

    var body: some View {
        let colors = TaleedButtonColors.of(kind, state)
        let shape = RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
        let box = iconOnlyBoxSize ?? size.iconOnlySize
        content
            .foregroundStyle(colors.content)
            .padding(.horizontal, isIconOnly ? 0 : metrics.paddingX)
            .padding(.vertical, isIconOnly ? 0 : 4)
            .frame(
                minWidth: isIconOnly ? box : minWidth,
                maxWidth: isFullWidth ? .infinity : nil,
                minHeight: isIconOnly ? box : (kind.isHyperlink ? size.hyperlinkHeight : size.height)
            )
            .frame(width: isIconOnly ? box : nil, height: isIconOnly ? box : nil)
            .background {
                if let fill = colors.fill { shape.fill(fill) }
            }
            .overlay {
                if let border = colors.border { shape.strokeBorder(border, lineWidth: TaleedSize.buttonBorderWidth) }
            }
            .overlay(alignment: .bottom) {
                // The Login link's 2 pt bottom border along the frame's bottom edge.
                if kind == .hyperlinkUnderlined { Rectangle().fill(colors.content).frame(height: 2) }
            }
            .contentShape(shape)
            .minimumHitArea()
    }
}

/// A text button with optional leading and trailing icons and a loading state. Width hugs the label;
/// `isFullWidth` for full-width CTAs. The height is a minimum: the label wraps with large text.
struct TaleedButton: View {
    let title: String
    var kind: TaleedButtonKind = .secondary
    var size: TaleedButtonSize = .large
    var leadingIcon: TaleedIcon?
    var trailingIcon: TaleedIcon?
    /// Shows a spinner instead of the label and ignores taps; the colours stay the default ones.
    var isLoading = false
    var isFullWidth = false
    /// While loading, a small spinner before the label instead of in its place (a label that says what
    /// runs: "Publication…").
    var keepsLabelWhileLoading = false
    var minWidth: CGFloat?
    /// Overrides the colour of the leading icon (Login "Continue with email" uses `blue/600`).
    var leadingIconColor: Color?
    var forcedState: TaleedButtonState?
    /// Overrides the type's metrics (the modal actions).
    var metrics: TaleedButtonMetrics?
    let action: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let resolved = metrics ?? .of(kind, size)
        Button(action: action) {
            // While loading, the label is hidden outright (never faded under the spinner), its size kept.
            let hidesLabel = isLoading && !keepsLabelWhileLoading
            HStack(spacing: TaleedSize.buttonGap) {
                if isLoading, keepsLabelWhileLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(TaleedButtonColors.of(kind, .normal).content)
                } else if let leadingIcon {
                    TaleedIconView(leadingIcon, size: size.iconSize, color: leadingIconColor)
                }
                Text(title)
                    .taleedFont(resolved.textStyle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let trailingIcon {
                    TaleedIconView(trailingIcon, size: size.iconSize, color: nil)
                }
            }
            .opacity(hidesLabel ? 0 : 1)
            .animation(nil, value: hidesLabel)
            .overlay {
                if hidesLabel {
                    ProgressView()
                        .tint(TaleedButtonColors.of(kind, .normal).content)
                }
            }
        }
        // Loading keeps the Default colours even inside a disabled container.
        .buttonStyle(TaleedButtonStyle(kind: kind, size: size, isFullWidth: isFullWidth, minWidth: minWidth,
                                       metrics: resolved, forcedState: forcedState ?? (isLoading ? .normal : nil)))
        .allowsHitTesting(!isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? DesignSystemStrings.string(.commonLoading, locale: locale) : "")
    }
}

/// An icon-only button: a 32, 40 or 48 box with a 20, 24 or 28 icon (Tertiary Medium by default, as
/// on Android) and a 44 pt hit area. Needs an accessibility label. `isLoading` shows a spinner in the
/// icon's place and ignores taps.
struct TaleedIconOnlyButton: View {
    let icon: TaleedIcon
    let accessibilityLabel: String
    var kind: TaleedButtonKind = .tertiary
    var size: TaleedButtonSize = .medium
    var isLoading = false
    /// Overrides the icon colour while enabled.
    var iconColor: Color?
    /// Overrides the size's box (the icon keeps the size's), e.g. 44 beside a 44 pt field.
    var boxSize: CGFloat?
    var forcedState: TaleedButtonState?
    let action: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(TaleedButtonColors.of(kind, .normal).content)
                        .frame(width: size.iconOnlyIconSize - 4, height: size.iconOnlyIconSize - 4)
                } else if let iconColor, isEnabled {
                    iconImage.foregroundStyle(iconColor)
                } else {
                    iconImage
                }
            }
        }
        .buttonStyle(TaleedButtonStyle(kind: kind, size: size, isIconOnly: true, iconOnlyBoxSize: boxSize,
                                       forcedState: forcedState ?? (isLoading ? .normal : nil)))
        .allowsHitTesting(!isLoading)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isLoading ? DesignSystemStrings.string(.commonLoading, locale: locale) : "")
    }

    private var iconImage: some View {
        Image(taleed: icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size.iconOnlyIconSize, height: size.iconOnlyIconSize)
            .flipsForRightToLeftLayoutDirection(icon.isDirectional)
    }
}

#Preview("Buttons") {
    VStack(spacing: 12) {
        ForEach(TaleedButtonKind.allCases, id: \.self) { kind in
            TaleedButton(title: "Publish listing", kind: kind, leadingIcon: .plus) {}
        }
        TaleedButton(title: "Buy now", isLoading: true, isFullWidth: true) {}
        TaleedIconOnlyButton(icon: .caretLeft, accessibilityLabel: "Back", kind: .hyperlink) {}
        TaleedIconOnlyButton(icon: .heart, accessibilityLabel: "Save", isLoading: true) {}
    }
    .padding()
}
