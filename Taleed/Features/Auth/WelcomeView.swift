import SwiftUI

/// Welcome (Figma wireframe "Login" 76:3634, design/wireframes.md §5): the sky with floating items,
/// "Your next treasure is floating nearby.", the legal line, "Continue with email" and "Browse without
/// signing in". "Continue with phone" is not built: sign-in is email only.
///
/// Shown over the shell at first launch and after sign-out (decision 4).
struct WelcomeView: View {
    let onContinueWithEmail: () -> Void
    let onBrowse: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection

    /// The Figma frame the positions below are measured in.
    static let frame = CGSize(width: 440, height: 956)

    /// Where the headline starts, in the Figma frame: Figma's 438, a little higher so that a long second
    /// line (Arabic) ends above the camera and the dress hanger, below the pink knit.
    static let headlineTop: CGFloat = 428
    /// The legal line's box in the Figma frame: all the open sky from the camera's edge to the dress
    /// (the artwork does not mirror, so these are left-to-right in every language). Figma's centred 368
    /// frame holds two short English lines between the two; the French and Arabic ones take three.
    static let legalStart: CGFloat = 118
    static let legalEnd: CGFloat = 338

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                              height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
            ZStack {
                WelcomeArtwork(size: size)
                if dynamicTypeSize.isAccessibilitySize {
                    // Figma's hidden "scrim-gradient" (neutral/50): at accessibility sizes the text no longer
                    // fits the open sky, so the items fade behind it.
                    LinearGradient(stops: [.init(color: TaleedColor.neutral50.opacity(0.9), location: 0),
                                           .init(color: TaleedColor.neutral50.opacity(0.94), location: 0.94),
                                           .init(color: TaleedColor.neutral50, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .accessibilityHidden(true)
                }
                foreground(size: size, safeArea: proxy.safeAreaInsets)
            }
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea()
        }
        .background(TaleedColor.blue500.ignoresSafeArea())
    }

    /// The headline on the open sky under the pink knit (Figma: y 438), then the legal line and the two
    /// actions from the bottom up (Figma: the actions end 136 above the bottom edge). The column scrolls
    /// when large text makes it taller than the screen.
    private func foreground(size: CGSize, safeArea: EdgeInsets) -> some View {
        let scaleX = size.width / Self.frame.width
        let scaleY = size.height / Self.frame.height
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let minimumTop = safeArea.top + TaleedSpacing.s24
        return ScrollView {
            VStack(spacing: 0) {
                Text(l10n.string(.appWelcomeTitle))
                    .taleedFont(TaleedFont.loginHeadline)
                    .foregroundStyle(TaleedColor.navy900)
                    .multilineTextAlignment(.center)
                    // Two lines as in Figma: a longer line (French) shrinks a little instead of wrapping.
                    // Accessibility sizes wrap freely.
                    .lineLimit(isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(isAccessibilitySize ? 1 : 0.7)
                    .frame(maxWidth: 392 * scaleX)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, isAccessibilitySize ? minimumTop : max(minimumTop, Self.headlineTop * scaleY))
                Spacer(minLength: TaleedSpacing.s24)
                // Figma: legal 604, its frame 48 high, then 16 to the actions.
                legal(scaleX: scaleX, isAccessibilitySize: isAccessibilitySize)
                VStack(spacing: TaleedSpacing.s12) {
                    // With "Continue with phone" hidden, email is the only way in: it takes the phone
                    // button's mint Secondary look (the main CTA, decision D-10) and keeps its envelope.
                    TaleedButton(title: l10n.string(.appWelcomeContinueEmail), kind: .secondary, size: .large,
                                 leadingIcon: .envelope, isFullWidth: true, action: onContinueWithEmail)
                    TaleedButton(title: l10n.string(.appWelcomeBrowse), kind: .hyperlinkUnderlined, size: .large,
                                 action: onBrowse)
                }
                .padding(.top, 32 * scaleY)
                .padding(.horizontal, max(0, 36 * scaleX - TaleedSpacing.s16))
            }
            .padding(.horizontal, TaleedSpacing.s16)
            .padding(.bottom, max(136 * scaleY, safeArea.bottom + TaleedSpacing.s16))
            .frame(maxWidth: .infinity, minHeight: size.height)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    /// The legal line in the sky between the camera and the dress, from the camera's edge on (left to
    /// right as the artwork, the text itself in the reading direction). Accessibility sizes use the
    /// whole width over the scrim.
    @ViewBuilder
    private func legal(scaleX: CGFloat, isAccessibilitySize: Bool) -> some View {
        let text = LegalText(text: l10n.string(.appWelcomeLegal), style: TaleedFont.legal, color: TaleedColor.navy900,
                             linkColor: TaleedColor.navy900)
        if isAccessibilitySize {
            text.frame(maxWidth: .infinity)
        } else {
            // The column has 16 pt of padding on each side.
            text
                .environment(\.layoutDirection, layoutDirection)
                .frame(width: (Self.legalEnd - Self.legalStart) * scaleX)
                .padding(.leading, max(0, Self.legalStart * scaleX - TaleedSpacing.s16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

/// The sky and the eight floating items, placed as in Figma (unrotated top-left, rotated about it)
/// and scaled to the screen. Photos never mirror in Arabic. They float gently unless Reduce Motion is on.
private struct WelcomeArtwork: View {
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    private struct Item {
        let image: TaleedImage
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        /// Figma's angle: positive turns counter-clockwise on screen.
        let rotation: Double
    }

    private static let items: [Item] = [
        Item(image: .loginBrownBag, x: 3, y: 38, width: 184, height: 200, rotation: -12),
        Item(image: .loginBlueTop, x: 216, y: 105, width: 168, height: 100, rotation: 10),
        Item(image: .loginPinkShirt, x: 98, y: 232, width: 226, height: 156, rotation: -12),
        Item(image: .loginHeadphones, x: 346, y: 246, width: 120, height: 118, rotation: 0),
        Item(image: .loginPinkCamera, x: -24, y: 545, width: 140, height: 148, rotation: 12),
        Item(image: .loginGreenDress, x: 307, y: 521, width: 182, height: 265, rotation: 12),
        Item(image: .loginDrapedFabric, x: -12, y: 786, width: 232, height: 198, rotation: -8),
        Item(image: .loginSunglasses, x: 293, y: 849, width: 118, height: 60, rotation: -21.43),
    ]

    var body: some View {
        let scaleX = size.width / WelcomeView.frame.width
        let scaleY = size.height / WelcomeView.frame.height
        ZStack(alignment: .topLeading) {
            Image(taleed: .loginSky)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
            ForEach(Array(Self.items.enumerated()), id: \.offset) { index, item in
                Image(taleed: item.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: item.width * scaleX, height: item.height * scaleX)
                    .rotationEffect(.degrees(-item.rotation), anchor: .topLeading)
                    .offset(x: item.x * scaleX, y: item.y * scaleY)
                    .offset(y: isFloating ? (index.isMultiple(of: 2) ? -4 : 4) : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 3 + Double(index % 3) * 0.6)
                        .repeatForever(autoreverses: true), value: isFloating)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { isFloating = true } }
    }
}
