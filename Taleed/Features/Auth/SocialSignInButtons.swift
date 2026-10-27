import AuthenticationServices
import SwiftUI

/// "Continue with Apple" and "Continue with Google" above the email form of sign-in and sign-up, then the
/// "or" divider, as on the website (slice G, Showing the buttons). Nothing shows when `GET /config` offers
/// neither provider.
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
        if !availability.isEmpty {
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
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
                if let message = flow.social.message {
                    AuthFormMessage(text: l10n.text(for: message))
                }
                SocialDivider(text: l10n.string(.authSocialDivider))
                    .padding(.top, TaleedSpacing.s4)
            }
        }
    }

    private func handle(_ outcome: SocialSignInViewModel.Outcome) {
        switch outcome {
        case .signedIn, .suspended: onDone()
        case let .profileRequired(profile): flow.showFinishSignUp(profile)
        case .inviteRequired: flow.switchToRequestAccessAfterSocialSignIn()
        case .stayed: break
        }
    }
}

/// `SignInWithAppleButton` "Continue with Apple", black, at the Large button's size. Apple's label follows
/// the app language when the system has it.
private struct AppleSignInButton: View {
    let viewModel: SocialSignInViewModel
    let onOutcome: (SocialSignInViewModel.Outcome) -> Void
    @Environment(LanguageManager.self) private var l10n

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            viewModel.prepareApple(request)
        } onCompletion: { result in
            Task { onOutcome(await viewModel.completeApple(result)) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: TaleedSize.buttonLargeHeight)
        .clipShape(RoundedRectangle(cornerRadius: TaleedSize.buttonRadius, style: .continuous))
        .overlay {
            if viewModel.pending == .apple {
                RoundedRectangle(cornerRadius: TaleedSize.buttonRadius, style: .continuous)
                    .fill(Color.black)
                    .overlay { ProgressView().tint(.white) }
            }
        }
        .environment(\.locale, l10n.language.locale)
        // VoiceOver reads the app language even when Apple's label follows the system's.
        .accessibilityLabel(l10n.string(.authContinueWithApple))
        .disabled(viewModel.isLoading)
        .accessibilityIdentifier("auth.apple")
    }
}

/// "Continue with Google" (Google's branding guidelines, light theme): white fill, a 1 pt #747775 border,
/// the standard "G" on the leading side and the #1F1F1F label. Google's own colours, not Taleed tokens.
struct GoogleSignInButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    static let fill = Color.white
    static let pressedFill = Color(taleedHex: 0xF2F2F2)
    static let border = Color(taleedHex: 0x747775)
    static let label = Color(taleedHex: 0x1F1F1F)

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
