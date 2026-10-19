import SwiftUI

/// Request an invite (website `request-access-form.tsx`): first and family name, email, phone
/// (optional), referral code, message (optional), "Request access". Once sent: "Request received!".
struct RequestAccessFormView: View {
    @Bindable var viewModel: RequestAccessViewModel
    let flow: AuthFlowModel
    @Environment(LanguageManager.self) private var l10n
    @FocusState private var firstNameFocused: Bool
    @FocusState private var lastNameFocused: Bool
    @FocusState private var emailFocused: Bool
    @FocusState private var phoneFocused: Bool
    @FocusState private var referralFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSize.bottomSheetGap) {
            AuthSubtitle(text: l10n.string(.authRequestAccessSubtitle))

            if let done = viewModel.done {
                doneView(done)
            } else {
                if flow.showsInviteRequired {
                    InlineAlert(kind: .info, title: l10n.string(.appErrorInviteRequired))
                }
                fields.disabled(viewModel.isLoading)

                if let message = viewModel.formMessage {
                    AuthFormMessage(text: l10n.text(for: message),
                                    actionTitle: viewModel.offersSignIn ? l10n.string(.authLoginCta) : nil,
                                    action: viewModel.offersSignIn ? { flow.show(.signIn) } : nil)
                }

                TaleedButton(title: l10n.string(.authRequestAccessCta), kind: .secondary, size: .large,
                             isLoading: viewModel.isLoading, isFullWidth: true, action: submit)
            }

            AuthFooterLink(prompt: l10n.string(.authHaveAccount), action: l10n.string(.authLoginCta)) {
                flow.show(.signIn)
            }
        }
        .padding(.bottom, TaleedSpacing.s8)
    }

    @ViewBuilder
    private func doneView(_ done: RequestAccessViewModel.Done) -> some View {
        switch done {
        case .received:
            InlineAlert(kind: .success, title: l10n.string(.authRequestAccessSuccessTitle),
                        message: l10n.string(.authRequestAccessSuccessBody))
                .onAppear {
                    AccessibilityNotification.Announcement(l10n.string(.authRequestAccessSuccessTitle)).post()
                }
        case .alreadyRequested:
            AuthFormMessage(text: l10n.string(.authRequestAccessAlreadyRequested), kind: .info)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: TaleedSize.bottomSheetGap) {
            TaleedTextField(label: l10n.string(.authFirstName), text: $viewModel.firstName, error: error(.firstName),
                            showsClearButton: false, focus: $firstNameFocused)
                .textContentType(.givenName)
                .limitLength($viewModel.firstName, to: AuthRules.namePartMaxLength)
                .submitLabel(.next)
                .onSubmit { lastNameFocused = true }
            TaleedTextField(label: l10n.string(.authLastName), text: $viewModel.lastName, error: error(.lastName),
                            showsClearButton: false, focus: $lastNameFocused)
                .textContentType(.familyName)
                .limitLength($viewModel.lastName, to: AuthRules.namePartMaxLength)
                .submitLabel(.next)
                .onSubmit { emailFocused = true }
            TaleedTextField(label: l10n.string(.authEmail), text: $viewModel.email, error: error(.email),
                            showsClearButton: false, focus: $emailFocused)
                .textContentType(.emailAddress)
                .emailInput()
                .limitLength($viewModel.email, to: AuthRules.emailMaxLength)
                .submitLabel(.next)
                .onSubmit { phoneFocused = true }
            TaleedTextField(label: optional(l10n.string(.authRequestAccessPhone)), text: $viewModel.phone,
                            error: error(.phone), showsClearButton: false, focus: $phoneFocused)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .limitLength($viewModel.phone, to: AuthRules.phoneMaxLength)
            // The website's label already says "(optional)".
            TaleedTextField(label: l10n.string(.authReferralCode), text: $viewModel.referralCode,
                            placeholder: l10n.string(.authReferralCodePlaceholder), error: error(.referralCode),
                            showsClearButton: false, focus: $referralFocused)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .limitLength($viewModel.referralCode, to: AuthRules.referralCodeFieldLength)
            TaleedTextArea(label: optional(l10n.string(.authRequestAccessMessage)), text: $viewModel.message,
                           placeholder: l10n.string(.authRequestAccessMessageHint), error: error(.message))
                .limitLength($viewModel.message, to: AuthRules.messageMaxLength)
        }
    }

    /// "Phone number (optional)", as the website's label.
    private func optional(_ label: String) -> String {
        "\(label) (\(l10n.string(.commonOptional)))"
    }

    private func error(_ field: RequestAccessViewModel.Field) -> String? {
        viewModel.fieldErrors[field].map(l10n.text(for:))
    }

    private func submit() {
        Task {
            await viewModel.submit()
            switch viewModel.firstFieldInError {
            case .firstName: firstNameFocused = true
            case .lastName: lastNameFocused = true
            case .email: emailFocused = true
            case .phone: phoneFocused = true
            case .referralCode: referralFocused = true
            case .message, nil: break
            }
        }
    }
}
