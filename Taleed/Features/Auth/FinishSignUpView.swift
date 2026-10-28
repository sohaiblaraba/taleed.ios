import SwiftUI

/// The finish step (slice G, The finish step), built from the sign-up form: "Signed in as {email}", first and
/// family name, username with its hint, the optional referral code, "Create my account" and the terms line.
/// Figma has no frame for it.
struct FinishSignUpFormView: View {
    @Bindable var viewModel: FinishSignUpViewModel
    let flow: AuthFlowModel
    let onDone: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts
    @Environment(\.sheetScrollProxy) private var scrollProxy
    @FocusState private var firstNameFocused: Bool
    @FocusState private var lastNameFocused: Bool
    @FocusState private var usernameFocused: Bool
    @FocusState private var referralFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSize.bottomSheetGap) {
            AuthSubtitle(text: l10n.string(.authFinishSubtitle))

            // The provider's email, read-only (an Apple private relay address shows as it is).
            HStack(spacing: TaleedSpacing.s8) {
                TaleedIconView(.envelope, size: 20, color: TaleedColor.textBody)
                    .accessibilityHidden(true)
                Text(l10n.format(.authFinishSignedInAs, viewModel.profile.email.isolatedLeftToRight))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("finish.email")

            fields.disabled(viewModel.isLoading)

            if let message = viewModel.message {
                AuthFormMessage(text: l10n.text(for: message))
            }

            TaleedButton(title: l10n.string(.authRegisterCta), kind: .secondary, size: .large,
                         isLoading: viewModel.isLoading, isFullWidth: true, action: submit)
                .accessibilityIdentifier("finish.submit")

            LegalText(text: l10n.string(.authTermsConsent))
                .frame(maxWidth: .infinity)

            // Back to sign-in; leaving the step drops the signup token (it lives in memory only).
            TaleedButton(title: l10n.string(.commonBack), kind: .hyperlink, size: .large, leadingIcon: .caretLeft) {
                flow.show(.signIn)
            }
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("finish.back")
        }
        .padding(.bottom, TaleedSpacing.s8)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: TaleedSize.bottomSheetGap) {
            TaleedTextField(label: l10n.string(.authFirstName), text: $viewModel.firstName,
                            error: error(.firstName), showsClearButton: false, focus: $firstNameFocused)
                .textContentType(.givenName)
                .limitLength($viewModel.firstName, to: AuthRules.namePartMaxLength)
                .submitLabel(.next)
                .onSubmit { lastNameFocused = true }
                .id(FinishSignUpViewModel.Field.firstName)
            TaleedTextField(label: l10n.string(.authLastName), text: $viewModel.lastName,
                            error: error(.lastName), showsClearButton: false, focus: $lastNameFocused)
                .textContentType(.familyName)
                .limitLength($viewModel.lastName, to: AuthRules.namePartMaxLength)
                .submitLabel(.next)
                .onSubmit { usernameFocused = true }
                .id(FinishSignUpViewModel.Field.lastName)
            TaleedTextField(label: l10n.string(.authUsername), text: $viewModel.username,
                            helper: l10n.string(.appAuthUsernameHint), error: error(.username), showsClearButton: false,
                            focus: $usernameFocused)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .limitLength($viewModel.username, to: AuthRules.usernameMaxLength)
                .submitLabel(.next)
                .onSubmit { referralFocused = true }
                .id(FinishSignUpViewModel.Field.username)
            TaleedTextField(label: l10n.string(.authReferralCode), text: $viewModel.referralCode,
                            placeholder: l10n.string(.authReferralCodePlaceholder), error: error(.referralCode),
                            showsClearButton: false, focus: $referralFocused)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .limitLength($viewModel.referralCode, to: AuthRules.referralCodeFieldLength)
                .submitLabel(.done)
                .onSubmit(submit)
                .id(FinishSignUpViewModel.Field.referralCode)
        }
    }

    private func error(_ field: FinishSignUpViewModel.Field) -> String? {
        viewModel.fieldErrors[field].map(l10n.text(for:))
    }

    private func submit() {
        Task {
            switch await viewModel.submit() {
            case let .signedUp(firstName):
                // The email is already verified: the welcome without "check your email".
                toasts.show(l10n.format(.authWelcomeToast, firstName))
                onDone()
            case .expired:
                flow.returnToSignIn(.finishExpired)
            case .emailTaken:
                flow.returnToSignIn(.emailTaken)
            case .inviteRequired:
                flow.switchToRequestAccessAfterSocialSignIn()
            case .failed:
                focusFirstError()
            }
        }
    }

    private func focusFirstError() {
        if let field = viewModel.firstFieldInError {
            scrollProxy?.scrollAnimated(to: field, anchor: .top)
        }
        switch viewModel.firstFieldInError {
        case .firstName: firstNameFocused = true
        case .lastName: lastNameFocused = true
        case .username: usernameFocused = true
        case .referralCode: referralFocused = true
        case nil: break
        }
    }
}
