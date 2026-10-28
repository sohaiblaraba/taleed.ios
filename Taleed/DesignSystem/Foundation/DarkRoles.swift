import SwiftUI

/// Colours that screens draw from the fixed scales, with a dark value (dark-mode.md: every app colour
/// has both). Light keeps the scale value (Figma); dark takes the dark-mode.md role of the same use.
/// The Android app has the same roles with the same values.
extension TaleedColor {
    // MARK: Brand tints (the soft blue fills) and the blue on them

    /// `blue/50` fills: the active tab pill, category chips, the tertiary button, selected cards. Dark: `brandSoft`.
    static let brandTint = blue50.inDark(brandSoft)
    /// `blue/100` fills: a pressed tint, the info alert, the avatar circle. Dark #22306A.
    static let brandTintStrong = blue100.inDark(Color(taleedHex: 0x22306A))
    /// `blue/100` borders around a tint (tertiary and active icon buttons). Dark: `brandSoftBorder`.
    static let brandTintBorder = blue100.inDark(brandSoftBorder)
    /// `blue/200` borders and dividers on a tint (selected choice chip, promo strip). Dark: `brandSoftBorder`.
    static let brandTintBorderStrong = blue200.inDark(brandSoftBorder)
    /// `blue/600` text and icons: the active tab, links, icons on a tint. Dark: `brandPrimary`.
    static let brandEmphasis = blue600.inDark(brandPrimary)
    /// `blue/700` text on a tint (promo strip, avatar initials). Dark: `brandDark`.
    static let brandOnTint = blue700.inDark(brandDark)
    /// `blue/800` icons on a tint (category chips). Dark: `brandDark`.
    static let brandOnTintStrong = blue800.inDark(brandDark)

    // MARK: Buttons and links

    /// The primary button's label (`blue/50`). Dark: `onBrandPrimary`.
    static let primaryButtonContent = blue50.inDark(onBrandPrimary)
    /// The primary button's border (`blue/600`). Dark: the fill (`brandPrimary`).
    static let primaryButtonBorder = blue600.inDark(brandPrimary)
    /// The pressed primary button (`blue/600`). Dark #A3B8FF, a step lighter than the fill.
    static let primaryButtonPressed = blue600.inDark(Color(taleedHex: 0xA3B8FF))
    /// The disabled primary button (`blue/200`). Dark: `surfaceSubtle`, the disabled send button's grey: a
    /// blue fill read as enabled in dark.
    static let primaryButtonDisabled = blue200.inDark(surfaceSubtle)
    /// The disabled primary button's label (`blue/50`). Dark #8A94AC (`onControlDisabledFill`).
    static let primaryButtonDisabledContent = blue50.inDark(Color(taleedHex: 0x8A94AC))
    /// The disabled secondary button (`mint/100` fill, `mint/200` border, `navy/300` label). Dark: the
    /// disabled primary's grey, so every disabled filled button looks the same in dark.
    static let secondaryButtonDisabled = mint100.inDark(surfaceSubtle)
    static let secondaryButtonDisabledBorder = mint200.inDark(surfaceSubtle)
    static let secondaryButtonDisabledContent = navy300.inDark(Color(taleedHex: 0x8A94AC))
    /// A pressed link (`blue/600`). Dark: `brandDark`.
    static let linkPressed = blue600.inDark(brandDark)
    /// The underlined link (`blue/900`). Dark: `textPrimary`.
    static let linkStrong = blue900.inDark(textPrimary)
    /// The pressed underlined link (`blue/700`). Dark: `textBody`.
    static let linkStrongPressed = blue700.inDark(textBody)
    /// Disabled links and tertiary labels (`blue/200`). Dark: `borderField`.
    static let linkDisabled = blue200.inDark(borderField)

    // MARK: Disabled, muted and inverse

    /// Disabled labels (`navy/300`). Dark #6B7590 (3.8:1 on `surfacePrimary`).
    static let contentDisabled = navy300.inDark(Color(taleedHex: 0x6B7590))
    /// Disabled icons (`navy/400`). Dark #6B7590.
    static let iconDisabled = navy400.inDark(Color(taleedHex: 0x6B7590))
    /// A disabled control's fill (`navy/200`, the send button). Dark: `surfaceSubtle`.
    static let controlDisabledFill = navy200.inDark(surfaceSubtle)
    /// Muted icons (`navy/500`, the views count). Dark: `textSecondary`.
    static let iconMuted = navy500.inDark(textSecondary)
    /// The info alert's message (`navy/700`). Dark: `textBody`.
    static let infoText = navy700.inDark(textBody)
    /// The 8 pt band between app-bar sections (`navy/50`). Dark: `surfaceGrouped`.
    static let sectionBand = navy50.inDark(surfaceGrouped)
    /// The selected category chip (`navy/800`). Dark: `textPrimary`, an inverted pill.
    static let inverseFill = navy800.inDark(textPrimary)
    /// Text and icons on `inverseFill` (white). Dark: `surfaceGrouped`.
    static let onInverseFill = Color(taleedLight: 0xFFFFFF, dark: 0x0B1120)
    /// The switch's thumb (white). Dark: `textPrimary`, a light thumb as on the system switch.
    static let toggleThumb = surfacePrimary.inDark(textPrimary)
    /// The dimming behind a confirmation modal (`text/primary` at 50 %). Dark: black at 60 %.
    static let modalDim = Color(taleedLight: 0x11182D, lightOpacity: 0.5, dark: 0x000000, darkOpacity: 0.6)
    /// Over a photo that uploads (`text/primary` at 35 %). Dark: black at 50 %.
    static let photoBusyOverlay = Color(taleedLight: 0x11182D, lightOpacity: 0.35, dark: 0x000000, darkOpacity: 0.5)
    /// The icon on `controlDisabledFill` (white, the send button). Dark #8A94AC.
    static let onControlDisabledFill = Color(taleedLight: 0xFFFFFF, dark: 0x8A94AC)
    /// The dark toast and the dark controls on photos (`text/primary` in light). Dark: `darkSurface`, so it stays dark.
    static let toastDark = textPrimary.inDark(darkSurface)

    // MARK: Mint

    /// `mint/50` fills (photo uploader, mint-soft button). Dark: `successSoft`.
    static let mintTint = mint50.inDark(successSoft)
    /// `mint/100` borders and fills on a mint tint. Dark #1D4A3B.
    static let mintTintBorder = mint100.inDark(Color(taleedHex: 0x1D4A3B))
    /// `mint/500` icons on a tint. Dark: `feedbackSuccess`.
    static let mintIcon = mint500.inDark(feedbackSuccess)
    /// `mint/600` text on a tint. Dark: `feedbackSuccess`.
    static let mintText = mint600.inDark(feedbackSuccess)
    /// `mint/900` text on a mint tint (not on the `mint/400` fill, which stays). Dark: `feedbackSuccess`.
    static let mintOnTint = mint900.inDark(feedbackSuccess)

    /// The roles above, for the design-system gallery (light value from the scale, dark value as above).
    static let darkRoleCatalog: [ColorToken] = [
        ("brandTint", brandTint, 0xF1F8FF, 0x1A2550), ("brandTintStrong", brandTintStrong, 0xD9E8FF, 0x22306A),
        ("brandTintBorder", brandTintBorder, 0xD9E8FF, 0x34478F),
        ("brandTintBorderStrong", brandTintBorderStrong, 0xACC8FF, 0x34478F),
        ("brandEmphasis", brandEmphasis, 0x1B43C3, 0x7C9BFF), ("brandOnTint", brandOnTint, 0x133293, 0xB9C7FF),
        ("brandOnTintStrong", brandOnTintStrong, 0x0B2166, 0xB9C7FF),
        ("primaryButtonContent", primaryButtonContent, 0xF1F8FF, 0x0B1120),
        ("primaryButtonBorder", primaryButtonBorder, 0x1B43C3, 0x7C9BFF),
        ("primaryButtonPressed", primaryButtonPressed, 0x1B43C3, 0xA3B8FF),
        ("primaryButtonDisabled", primaryButtonDisabled, 0xACC8FF, 0x26304A),
        ("primaryButtonDisabledContent", primaryButtonDisabledContent, 0xF1F8FF, 0x8A94AC),
        ("linkPressed", linkPressed, 0x1B43C3, 0xB9C7FF), ("linkStrong", linkStrong, 0x05123C, 0xEEF1F8),
        ("linkStrongPressed", linkStrongPressed, 0x133293, 0xC2C8D6), ("linkDisabled", linkDisabled, 0xACC8FF, 0x4A5675),
        ("contentDisabled", contentDisabled, 0xADB0BA, 0x6B7590), ("iconDisabled", iconDisabled, 0x9095A1, 0x6B7590),
        ("secondaryButtonDisabled", secondaryButtonDisabled, 0xE0F6EC, 0x26304A),
        ("secondaryButtonDisabledBorder", secondaryButtonDisabledBorder, 0xBCEED8, 0x26304A),
        ("secondaryButtonDisabledContent", secondaryButtonDisabledContent, 0xADB0BA, 0x8A94AC),
        ("controlDisabledFill", controlDisabledFill, 0xCACDD4, 0x26304A), ("iconMuted", iconMuted, 0x727887, 0x9AA3B8),
        ("infoText", infoText, 0x3E4558, 0xC2C8D6), ("sectionBand", sectionBand, 0xF7F8FA, 0x0B1120),
        ("inverseFill", inverseFill, 0x272E42, 0xEEF1F8), ("onInverseFill", onInverseFill, 0xFFFFFF, 0x0B1120),
        ("modalDim", modalDim, 0x11182D, 0x000000), ("photoBusyOverlay", photoBusyOverlay, 0x11182D, 0x000000),
        ("onControlDisabledFill", onControlDisabledFill, 0xFFFFFF, 0x8A94AC),
        ("toggleThumb", toggleThumb, 0xFFFFFF, 0xEEF1F8), ("toastDark", toastDark, 0x11182D, 0x1E2945),
        ("mintTint", mintTint, 0xF2FAF6, 0x0F2A22), ("mintTintBorder", mintTintBorder, 0xE0F6EC, 0x1D4A3B),
        ("mintIcon", mintIcon, 0x4AB08B, 0x4CD39F),
        ("mintText", mintText, 0x36896B, 0x4CD39F), ("mintOnTint", mintOnTint, 0x032117, 0x4CD39F),
    ].map { ColorToken(group: "dark role", name: $0.0, color: $0.1, hex: $0.2, opacity: 1, darkHex: $0.3, darkOpacity: 1) }
}
