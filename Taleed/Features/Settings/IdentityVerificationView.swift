import PhotosUI
import SwiftUI
import UIKit

/// "Vérification d’identité" (screens.md §2 and §7 G17; website `verification-form.tsx`, a card of
/// `/settings`; Figma draws no screen, so it is built from the design-system parts: the back app bar,
/// inline alerts, fields, the photo uploader's zone and the mint button).
///
/// The website's description with the badge icon, then by status: VERIFIED the success alert and the
/// legal name read-only with the locked hint; PENDING the info alert, no form; REJECTED the red alert
/// (the reviewer's note when there is one) above the form; NONE the form. The form: the legal name
/// (app step: the ID is checked against it), "Pièce d’identité" (camera or library; the preview with an
/// X), the privacy note, then "Envoyer ma demande" / "Renvoyer une demande". Reloads in the foreground
/// and on pull-to-refresh (the decision arrives as a notification).
struct IdentityVerificationView: View {
    @State private var model: IdentityVerificationViewModel
    @State private var choosesSource = false
    @State private var showsLibrary = false
    @State private var showsCamera = false
    @State private var pickedItem: PhotosPickerItem?
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts
    @Environment(SessionManager.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    /// The description's badge icon grows with its text.
    @ScaledMetric(relativeTo: .caption) private var headerIconSize: CGFloat = 20
    /// The description's font size (Body/Small), to centre the icon on its first line.
    @ScaledMetric(relativeTo: .caption) private var headerTextSize: CGFloat = 12

    init(dependencies: SettingsDependencies, store: AccountStore) {
        let uploads = dependencies.uploads
        _model = State(initialValue: IdentityVerificationViewModel(api: dependencies.verification, account: dependencies.account,
                                                                   store: store) { data throws(ApiError) in
            #if DEBUG
            if VerificationDebugFailures.fakesUpload { return UploadedPhoto(key: "debug/id-document", url: nil, thumbURL: nil) }
            #endif
            return try await uploads.upload(data, purpose: .idDocument)
        })
    }

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: l10n.string(.settingsVerificationTitle), onBack: { dismiss() })
        } content: {
            switch model.phase {
            case .loading:
                LoadingStateView()
            case let .failed(error):
                ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
            case let .loaded(status):
                content(status)
            }
        }
        // Again once the session is there (a link or a notification that opened this screen).
        .task(id: session.user?.id) { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refresh(automatic: true) }
        }
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            model.notice = nil
            switch notice {
            case .submitted: toasts.show(l10n.string(.settingsVerificationSubmitted))
            case .unreadablePhoto: toasts.show(l10n.string(.settingsVerificationUploadError), kind: .error)
            case let .refreshFailed(error): toasts.show(error: error)
            }
        }
        .taleedSheet(isPresented: $choosesSource) { sourceSheet }
        .photosPicker(isPresented: $showsLibrary, selection: $pickedItem, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.photoPicked(data)
                } else {
                    toasts.show(l10n.string(.settingsVerificationUploadError), kind: .error)
                }
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { image in
                showsCamera = false
                guard let data = image?.jpegData(compressionQuality: 0.95) else { return }
                model.photoPicked(data)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Content

    private func content(_ status: IdentityStatus) -> some View {
        ScrollViewReader { proxy in
            scrollContent(status)
                // A failed send: the reason comes into view (it shows above the button, which may be
                // at the bottom of the screen), as the profile form does for its field errors.
                .onChange(of: model.submitError) { _, failure in
                    guard failure != nil else { return }
                    withAnimation { proxy.scrollTo(Self.errorAnchor, anchor: .center) }
                }
        }
    }

    private static let errorAnchor = "verification.error"

    private func scrollContent(_ status: IdentityStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
                // The call to action is for a member who can still ask: verified, the banner says it all.
                if status != .verified { header }
                switch status {
                case .verified:
                    InlineAlert(kind: .success, title: l10n.string(.settingsVerificationVerified))
                        .accessibilityIdentifier("verification.verified")
                    lockedName
                case .pending:
                    InlineAlert(kind: .info, title: l10n.string(.settingsVerificationPending))
                        .accessibilityIdentifier("verification.pending")
                case let .rejected(note):
                    InlineAlert(kind: .error, title: rejectedText(note))
                        .accessibilityIdentifier("verification.rejected")
                    form(isResubmit: true)
                case .none:
                    form(isResubmit: false)
                }
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.vertical, TaleedSpacing.s16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refresh(automatic: false) }
        .accessibilityIdentifier("verification.scroll")
    }

    /// The website card's description, after its badge icon.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: TaleedSpacing.s8) {
            // On the first line, at the text's size.
            TaleedIconView(.sealCheck, size: min(headerIconSize, 40), color: TaleedColor.brandPrimary)
                .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[VerticalAlignment.center] + headerTextSize * 0.35 }
                .accessibilityHidden(true)
            Text(l10n.string(.settingsVerificationDescription))
                .taleedFont(TaleedFont.bodySmall)
                .foregroundStyle(TaleedColor.textSecondarySmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Votre dernière demande a été refusée : {note}" (the note as the reviewer wrote it, usually in
    /// French), or the sentence without a note.
    private func rejectedText(_ note: String?) -> String {
        guard let note else { return l10n.string(.settingsVerificationRejected) }
        return l10n.format(.settingsVerificationRejectedWithNote, note.isolatedByContent)
    }

    // MARK: Verified

    /// The legal name, read-only once verified, with the website's locked hint.
    @ViewBuilder
    private var lockedName: some View {
        if let profile = model.profile {
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                SectionTitle(text: l10n.string(.appVerificationNameTitle))
                TaleedTextField(label: l10n.string(.authFirstName), text: .constant(profile.firstName), showsClearButton: false)
                    .disabled(true)
                    .accessibilityIdentifier("verification.firstName")
                TaleedTextField(label: l10n.string(.authLastName), text: .constant(profile.lastName), showsClearButton: false)
                    .disabled(true)
                    .accessibilityIdentifier("verification.lastName")
                FieldHelper(text: l10n.string(.settingsNameLockedHint), color: TaleedColor.textSecondarySmall)
            }
            .padding(.top, TaleedSpacing.s8)
        }
    }

    // MARK: Form

    private func form(isResubmit: Bool) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            nameFields
            DocumentPhotoSlot(label: l10n.string(.settingsVerificationIdLabel), hint: l10n.string(.settingsVerificationIdHint),
                              image: model.photo.map { Image(uiImage: $0.preview) },
                              removeLabel: l10n.string(.appVerificationRemovePhoto), isEnabled: !model.isSubmitting,
                              onPick: pickPhoto, onRemove: model.removePhoto)
                .accessibilityIdentifier("verification.photo")
            Text(l10n.string(.settingsVerificationPrivacyNote))
                .taleedFont(TaleedFont.bodySmall)
                .foregroundStyle(TaleedColor.textSecondarySmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let failure = model.submitError {
                failureAlert(failure)
                    .id(Self.errorAnchor)
            }
            TaleedButton(title: l10n.string(isResubmit ? .settingsVerificationResubmit : .settingsVerificationSubmit),
                         kind: .secondary, size: .large, isLoading: model.isSubmitting, isFullWidth: true) {
                Task { await model.submit() }
            }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("verification.submit")
        }
        .padding(.top, TaleedSpacing.s8)
    }

    /// The legal name the ID is checked against (app step 1; slice E "The name").
    private var nameFields: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            SectionTitle(text: l10n.string(.appVerificationNameTitle))
            Text(l10n.string(.appVerificationNameHint))
                .taleedFont(TaleedFont.bodySmall)
                .foregroundStyle(TaleedColor.textSecondarySmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            TaleedTextField(label: l10n.string(.authFirstName),
                            text: Binding(get: { model.firstName },
                                          set: { model.firstName = AuthValidation.limited($0, to: AccountLimits.namePartMax) }),
                            error: nameMessage(model.nameError(.firstName)), showsClearButton: false)
                .textContentType(.givenName)
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("verification.firstName")
            TaleedTextField(label: l10n.string(.authLastName),
                            text: Binding(get: { model.lastName },
                                          set: { model.lastName = AuthValidation.limited($0, to: AccountLimits.namePartMax) }),
                            error: nameMessage(model.nameError(.lastName)), showsClearButton: false)
                .textContentType(.familyName)
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("verification.lastName")
        }
    }

    private func nameMessage(_ error: ProfileFieldError?) -> String? {
        switch error {
        case .nameLength?: l10n.format(.appAuthNameLength, AccountLimits.namePartMin, AccountLimits.namePartMax)
        case .nameLocked?: l10n.string(.settingsNameLockedHint)
        case .invalid?: l10n.string(.appCheckoutFieldInvalid)
        case .phoneInvalid?, .phoneRefused?, nil: nil
        }
    }

    /// Why the last send stopped, above the button.
    private func failureAlert(_ failure: VerificationSubmitError) -> some View {
        let (title, message) = failureText(failure)
        return InlineAlert(kind: .error, title: title, message: message)
            .announcesFieldError(title)
            .accessibilityIdentifier("verification.error")
    }

    private func failureText(_ failure: VerificationSubmitError) -> (String, String?) {
        let error = failure.error
        switch failure {
        case .name:
            return (l10n.message(for: error), nil)
        case .upload:
            // A photo the API refuses has its own reason; anything else is the website's upload error.
            switch error.code {
            case .fileTooLarge?, .unsupportedMediaType?, .rateLimited?: return (l10n.message(for: error), nil)
            default: return (l10n.string(.settingsVerificationUploadError), error == .network ? l10n.message(for: error) : nil)
            }
        case .submit:
            // The limit (5 a day): only the wait, since trying again now cannot work (Send is disabled).
            if case .rateLimited = error { return (l10n.message(for: error), nil) }
            // The website's sentence, with the lost connection.
            let detail: String? = error == .network ? l10n.message(for: error) : nil
            return (l10n.string(.settingsVerificationSubmitError), detail)
        }
    }

    // MARK: Picking

    /// With a camera: the rear camera or the library. Without one (the simulator): the library at once.
    private func pickPhoto() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            choosesSource = true
        } else {
            showsLibrary = true
        }
    }

    private var sourceSheet: some View {
        TaleedBottomSheet(title: l10n.string(.settingsVerificationIdLabel), onClose: { choosesSource = false }, content: {
            VStack(spacing: TaleedSpacing.s12) {
                TaleedButton(title: l10n.string(.appVisualTakePhoto), kind: .secondary, size: .large, isFullWidth: true) {
                    choosesSource = false
                    showsCamera = true
                }
                TaleedButton(title: l10n.string(.appSellPhotoLibrary), kind: .outline, size: .large, isFullWidth: true) {
                    choosesSource = false
                    showsLibrary = true
                }
            }
        })
    }
}
