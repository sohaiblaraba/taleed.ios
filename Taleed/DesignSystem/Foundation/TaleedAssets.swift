import SwiftUI

extension Image {
    /// A design-system icon as a template image (tint it with `foregroundStyle`).
    init(taleed icon: TaleedIcon) {
        self.init(icon.assetName, bundle: .main)
    }

    /// A brand mark, illustration or artwork image.
    init(taleed image: TaleedImage) {
        self.init(image.assetName, bundle: .main)
    }
}

/// Draws an icon at its design size and colour. Directional icons mirror in right-to-left layouts.
/// Icons are decorative: give the control around them an accessibility label.
struct TaleedIconView: View {
    let icon: TaleedIcon
    var size: CGFloat = 24
    /// Nil takes the surrounding foreground style (for example a button's content colour).
    var color: Color?

    init(_ icon: TaleedIcon, size: CGFloat = 24, color: Color? = TaleedColor.textPrimary) {
        self.icon = icon
        self.size = size
        self.color = color
    }

    var body: some View {
        Image(taleed: icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .modifier(OptionalForeground(color: color))
            .flipsForRightToLeftLayoutDirection(icon.isDirectional)
            .accessibilityHidden(true)
    }
}

private struct OptionalForeground: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.foregroundStyle(color)
        } else {
            content
        }
    }
}

/// Brand marks, illustrations and artwork in the asset catalog (`DesignSystem.xcassets`).
/// Photos and logos never mirror in right-to-left layouts.
enum TaleedImage: String, CaseIterable, Sendable {
    /// Vector wordmark, 95 x 24, `brand/primary`.
    case wordmark = "Brand/taleed-wordmark"
    /// The wordmark in white, for blue or photo backgrounds.
    case wordmarkWhite = "Brand/taleed-wordmark-white"
    /// 38 x 38 lettermark ("T" on `brand/primary`).
    case lettermark = "Brand/taleed-lettermark"
    /// Empty search: 84 circle `brandSoft` with a magnifying glass.
    case emptyStateSearch = "Illustrations/empty-state-search"
    /// Home hero banner photo (408 x 160 at 3x).
    case homeHeroBackground = "Home/home-hero-background"
    /// Home hero cut-out that pops out of the banner (408 x 184 at 3x).
    case homeHeroForeground = "Home/home-hero-foreground"
    /// Login sky background.
    case loginSky = "Login/login-sky-bg"
    case loginBrownBag = "Login/float-brown-bag"
    case loginBlueTop = "Login/float-blue-top"
    case loginPinkShirt = "Login/float-pink-shirt"
    case loginHeadphones = "Login/float-headphones"
    case loginPinkCamera = "Login/float-pink-camera"
    case loginGreenDress = "Login/float-green-dress"
    case loginDrapedFabric = "Login/float-draped-fabric"
    case loginSunglasses = "Login/float-sunglasses"

    var assetName: String { rawValue }
}
