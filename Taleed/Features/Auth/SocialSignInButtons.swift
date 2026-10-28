import AuthenticationServices
import SwiftUI

/// "Continue with Apple" and "Continue with Google" above the email form of sign-in and sign-up, then the
/// "or" divider, as on the website (slice G, Showing the buttons). A failed sign-in's message (a warning, as on
/// Android and the website) sits above the buttons. Nothing shows when `GET /config` offers neither provider,
/// except that message: `feature_disabled` can hide the last button and must still say why.
///
/// Apple comes first and has the same size as Google (App Store guideline 4.8: an equivalent option at least
/// as prominent). Apple's button is the system `SignInWithAppleButton` (black, Human Interface Guidelines);
/// Google's follows Google's branding guidelines (white, grey border, the four-colour "G"). Both take the
/// Large button's height (48) and radius (`radius.s`, 10) of the design system.
struct SocialSignInSection: View {
    let flow: AuthFlowModel
    let onDone: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.authDependencies) private var dependencies

    private var availability: SocialAvailability {
        dependencies?.socialAvailability() ?? SocialAvailability()
    }

    var body: some View {
        let availability = availability
        if !availability.isEmpty || flow.social.message != nil {
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                if let message = flow.social.message {
                    AuthFormMessage(text: l10n.text(for: message), kind: .warning)
                }
                if availability.apple {
                    AppleSignInButton(viewModel: flow.social, onOutcome: handle)
                }
                if availability.google {
                    GoogleSignInButton(title: l10n.string(.authContinueWithGoogle),
                                       isLoading: flow.social.pending == .google) {
                        Task { handle(await flow.social.signInWithGoogle()) }
                    }
                    .disabled(flow.social.isLoading)
                }
                if !availability.isEmpty {
                    SocialDivider(text: l10n.string(.authSocialDivider))
                        .padding(.top, TaleedSpacing.s4)
                }
            }
        }
    }

    private func handle(_ outcome: SocialSignInViewModel.Outcome) {
        switch outcome {
        case .signedIn, .suspended: onDone()
        case let .profileRequired(profile): flow.showFinishSignUp(profile)
        case let .inviteRequired(prefill): flow.switchToRequestAccessAfterSocialSignIn(prefill: prefill)
        case .stayed: break
        }
    }
}

/// `SignInWithAppleButton` "Continue with Apple", black in light and white in dark, at the Large button's size. Apple draws the label in
/// the device language, whatever the app language is (FB-11).
private struct AppleSignInButton: View {
    let viewModel: SocialSignInViewModel
    let onOutcome: (SocialSignInViewModel.Outcome) -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            viewModel.prepareApple(request)
        } onCompletion: { result in
            Task { onOutcome(await viewModel.completeApple(result)) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: TaleedSize.buttonLargeHeight)
        .clipShape(RoundedRectangle(cornerRadius: TaleedSize.buttonRadius, style: .continuous))
        .overlay {
            if viewModel.pending == .apple {
                RoundedRectangle(cornerRadius: TaleedSize.buttonRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white : Color.black)
                    .overlay { ProgressView().tint(colorScheme == .dark ? Color.black : Color.white) }
            }
        }
        // VoiceOver reads the app language; the visible label stays in the device language (FB-11).
        .accessibilityLabel(l10n.string(.authContinueWithApple))
        .disabled(viewModel.isLoading)
        .accessibilityIdentifier("auth.apple")
    }
}

/// "Continue with Google" (Google's branding guidelines): light theme, white fill, a 1 pt #747775 border and
/// the #1F1F1F label; dark theme, #131314 fill, a #8E918F border and the #E3E3E3 label; the standard "G" on
/// the leading side. Google's own colours, not Taleed tokens.
struct GoogleSignInButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    static let fill = Color(taleedLight: 0xFFFFFF, dark: 0x131314)
    static let pressedFill = Color(taleedLight: 0xF2F2F2, dark: 0x262628)
    static let border = Color(taleedLight: 0x747775, dark: 0x8E918F)
    static let label = Color(taleedLight: 0x1F1F1F, dark: 0xE3E3E3)

    var body: some View {
        Button(action: action) {
            HStack(spacing: TaleedSpacing.s12) {
                if isLoading {
                    ProgressView().tint(Self.label).frame(width: 20, height: 20)
                } else {
                    Image("google-g")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .taleedFont(TaleedFont.buttonLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Self.label)
            .padding(.horizontal, TaleedSize.buttonLargePaddingX)
            .frame(maxWidth: .infinity, minHeight: TaleedSize.buttonLargeHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(GoogleButtonStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier("auth.google")
    }
}

private struct GoogleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: TaleedSize.buttonRadius, style: .continuous)
        configuration.label
            .background(shape.fill(configuration.isPressed ? GoogleSignInButton.pressedFill : GoogleSignInButton.fill))
            .overlay(shape.strokeBorder(GoogleSignInButton.border, lineWidth: TaleedSize.buttonBorderWidth))
    }
}

/// The website's divider: a hairline, "or", a hairline.
private struct SocialDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: TaleedSpacing.s12) {
            line
            Text(text)
                .taleedFont(TaleedFont.caption)
                .foregroundStyle(TaleedColor.textSecondarySmall)
            line
        }
        .accessibilityElement(children: .combine)
    }

    private var line: some View {
        Rectangle()
            .fill(TaleedColor.borderSubtle)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
