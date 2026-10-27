import SwiftUI

/// Sign up (website `register-form.tsx`): "Continue with Apple" and "Continue with Google" with the "or"
/// divider (slice G), first and family name, username with its hint, email,
/// password, the optional referral code, "Create my account", the passive terms line, and "Already
/// have an account? Log in". No terms checkbox and no newsletter opt-in (screens.md §7 G1).
struct SignUpFormView: View {
    @Bindable var viewModel: SignUpViewModel
    let flow: AuthFlowModel
    let onDone: () -> Void
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts
    @FocusState private var firstNameFocused: Bool
    @FocusState private var lastNameFocused: Bool
    @FocusState private var usernameFocused: Bool
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool
    @FocusState private var referralFocused: Bool
    @Environment(\.sheetScrollProxy) private var scrollProxy

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSize.bottomSheetGap) {
            AuthSubtitle(text: l10n.string(.authRegisterSubtitle))

            SocialSignInSection(flow: flow, onDone: onDone)
                .disabled(viewModel.isLoading)

            fields.disabled(viewModel.isLoading || flow.social.isLoading)

            if let message = viewModel.message {
                AuthFormMessage(text: l10n.text(for: message))
            }

            TaleedButton(title: l10n.string(.authRegisterCta), kind: .secondary, size: .large,
                         isLoading: viewModel.isLoading, isFullWidth: true, action: submit)

            LegalText(text: l10n.string(.authTermsConsent))
                .frame(maxWidth: .infinity)

            AuthFooterLink(prompt: l10n.string(.authHaveAccount), action: l10n.string(.authLoginCta)) {
                flow.show(.signIn)
            }
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
                .id(SignUpViewModel.Field.firstName)
            TaleedTextField(label: l10n.string(.authLastName), text: $viewModel.lastName,
                            error: error(.lastName), showsClearButton: false, focus: $lastNameFocused)
                .textContentType(.familyName)
                .limitLength($viewModel.lastName, to: AuthRules.namePartMaxLength)
                .submitLabel(.next)
                .onSubmit { usernameFocused = true }
                .id(SignUpViewModel.Field.lastName)
            // The helper gives the whole rule (length and characters); an error names only the part that failed.
            TaleedTextField(label: l10n.string(.authUsername), text: $viewModel.username,
                            helper: l10n.string(.appAuthUsernameHint), error: error(.username), showsClearButton: false,
                            focus: $usernameFocused)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .limitLength($viewModel.username, to: AuthRules.usernameMaxLength)
                .submitLabel(.next)
                .onSubmit { emailFocused = true }
                .id(SignUpViewModel.Field.username)
            VStack(alignment: .leading, spacing: TaleedSpacing.s4) {
                TaleedTextField(label: l10n.string(.authEmail), text: $viewModel.email, leadingIcon: .envelope,
                                error: error(.email), showsClearButton: false, focus: $emailFocused)
                    .textContentType(.emailAddress)
                    .emailInput()
                    .limitLength($viewModel.email, to: AuthRules.emailMaxLength)
                    .submitLabel(.next)
                    .onSubmit { passwordFocused = true }
                if viewModel.offersSignIn {
                    // `email_taken`: sign in, or reset the password (api-guide.md, Error codes).
                    HStack(spacing: TaleedSpacing.s16) {
                        TaleedButton(title: l10n.string(.authLoginCta), kind: .hyperlink, size: .small) {
                            flow.show(.signIn)
                        }
                        TaleedButton(title: l10n.string(.authForgotPassword), kind: .hyperlink, size: .small) {
                            flow.show(.forgotPassword)
                        }
                    }
                }
            }
            .id(SignUpViewModel.Field.email)
            TaleedTextField(label: l10n.string(.authPassword), text: $viewModel.password, leadingIcon: .lockKey,
                            error: error(.password), isSecure: true, focus: $passwordFocused)
                .textContentType(Self.newPasswordContentType)
                .limitLength($viewModel.password, to: AuthRules.passwordMaxLength)
                .submitLabel(.next)
                .onSubmit { referralFocused = true }
                .id(SignUpViewModel.Field.password)
            TaleedTextField(label: l10n.string(.authReferralCode), text: $viewModel.referralCode,
                            placeholder: l10n.string(.authReferralCodePlaceholder), error: error(.referralCode),
                            showsClearButton: false, focus: $referralFocused)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .limitLength($viewModel.referralCode, to: AuthRules.referralCodeFieldLength)
                .submitLabel(.done)
                .onSubmit(submit)
                .id(SignUpViewModel.Field.referralCode)
        }
    }

    /// Release builds offer a strong password. Debug builds do not: the Simulator covers the field with
    /// "Automatic Strong Password" and nothing can be typed in it.
    private static var newPasswordContentType: UITextContentType {
        #if DEBUG
        .password
        #else
        .newPassword
        #endif
    }

    private func error(_ field: SignUpViewModel.Field) -> String? {
        viewModel.fieldErrors[field].map(l10n.text(for:))
    }

    private func submit() {
        Task {
            switch await viewModel.submit() {
            case let .signedUp(firstName):
                // The website's welcome and "check your email" toasts, as one (shown 10 s, as on the web).
                let welcome = l10n.format(.authWelcomeToast, firstName)
                toasts.show("\(welcome)\n\(l10n.string(.authVerifyEmailToast))", duration: 10)
                onDone()
            case .inviteRequired:
                flow.switchToRequestAccess()
            case .failed:
                focusFirstError()
            }
        }
    }

    /// Focus on the first field in error, scrolled to the top of the sheet.
    private func focusFirstError() {
        if let field = viewModel.firstFieldInError {
            scrollProxy?.scrollAnimated(to: field, anchor: .top)
        }
        switch viewModel.firstFieldInError {
        case .firstName: firstNameFocused = true
        case .lastName: lastNameFocused = true
        case .username: usernameFocused = true
        case .email: emailFocused = true
        case .password: passwordFocused = true
        case .referralCode: referralFocused = true
        case nil: break
        }
    }
}
