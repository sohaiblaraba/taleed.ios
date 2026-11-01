import SwiftUI

/// "Enable notifications" (plan/push-prompt.md): full screen over the main tabs, once per installation, the
/// first time a signed-in member is on them (`MainShellView`). No Figma frame: the design system's empty-state
/// pattern (the icon in a `brandSoft` circle, larger here, as on Android), a title and a body, the main CTA
/// ("Enable") and a text button ("Not now"). No close icon. Scrolls when the text is large.
struct PushPromptView: View {
    @Environment(PushRegistration.self) private var push
    @Environment(LanguageManager.self) private var l10n
    @State private var isEnabling = false

    /// The empty-state circle (84, icon 34) made larger: the screen is about this icon alone.
    private static let circleSize: CGFloat = 112
    private static let iconSize: CGFloat = 48

    var body: some View {
        CenteredStateColumn {
            TaleedIconView(.bell, size: Self.iconSize, color: TaleedColor.brandPrimary)
                .frame(width: Self.circleSize, height: Self.circleSize)
                .background(Circle().fill(TaleedColor.brandSoft))
                .accessibilityHidden(true)
                .padding(.bottom, TaleedSpacing.s8)
            Text(l10n.string(.pwaPushTitle))
                .taleedFont(TaleedFont.title2)
                .foregroundStyle(TaleedColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("pushPrompt.title")
            Text(l10n.string(.pwaPushBody))
                .taleedFont(TaleedFont.bodyLarge)
                .foregroundStyle(TaleedColor.textBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
            TaleedButton(title: l10n.string(.pwaPushEnable), kind: .secondary, size: .large, isLoading: isEnabling,
                         isFullWidth: true) {
                isEnabling = true
                Task {
                    await push.promptDidEnable()
                    isEnabling = false
                }
            }
            .padding(.top, TaleedSpacing.s8)
            .accessibilityIdentifier("pushPrompt.enable")
            TaleedButton(title: l10n.string(.appPushPromptNotNow), kind: .hyperlink, size: .large) {
                push.promptDidDecline()
            }
            .disabled(isEnabling)
            .accessibilityIdentifier("pushPrompt.notNow")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .onAppear { push.promptDidAppear() }
        .analyticsScreen(.pushPermission)
    }
}
