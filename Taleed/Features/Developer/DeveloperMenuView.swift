#if DEBUG || TALEED_TEST_TOOLS
import SwiftUI

/// The developer menu (debug builds; Settings → Developer menu): what the build talks to, sign out, open a
/// link through the router, move a demo parcel forward (`POST /orders/{id}/shipment/simulate`, slice F),
/// send test notifications and crash on purpose (slice J), and empty the caches.
///
/// Staging builds show it as "Test tools", with only the build, the parcel step, the test notifications and
/// the test crash. Release builds have neither. Its copy is English and never reaches members.
struct DeveloperMenuView: View {
    #if DEBUG
    static let title = "Developer menu"
    #else
    static let title = "Test tools"
    #endif

    @Environment(SessionManager.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(LanguageManager.self) private var l10n
    @Environment(\.appEnvironment) private var environment
    @Environment(\.developmentApi) private var developmentApi
    @Environment(\.dismiss) private var dismiss

    @State private var orderId = ""
    @State private var step: ShipmentSimulationStep = .transit
    @State private var isSimulating = false
    @State private var simulationResult: (kind: TaleedFeedbackKind, text: String)?
    @State private var link = ""
    @State private var isUploading = false
    @State private var upload: UploadedPhoto?
    @State private var uploadError: String?

    var body: some View {
        ShellScreen {
            TaleedTopAppBar(title: Self.title, onBack: { dismiss() })
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Build")
                    ListRow(label: "API", trailingText: environment.apiBaseURL.absoluteString.isolatedLeftToRight)
                    ListRow(label: "Version", trailingText: "\(environment.appVersion) (\(environment.buildNumber))".isolatedLeftToRight)
                    ListRow(label: "URL scheme", trailingText: LinkRouter.appScheme.isolatedLeftToRight)
                    ListRow(label: "Language", trailingText: l10n.language.rawValue)

                    #if DEBUG
                    section("Session")
                    ListRow(label: session.user.map { "Signed in as \($0.handle ?? $0.id)" } ?? "Signed out")
                    if session.isSignedIn {
                        TaleedButton(title: "Sign out", kind: .tertiary, size: .large, isFullWidth: true) {
                            session.signOut()
                        }
                        .padding(.horizontal, TaleedLayout.screenMargin)
                        .padding(.top, TaleedSpacing.s8)
                    }
                    #endif

                    section("Simulate parcel step")
                    simulateShipment

                    section("Send test notifications")
                    if let developmentApi {
                        TestNotificationsSection(api: developmentApi)
                    }

                    section("Crash reporting")
                    CrashTestSection()

                    #if DEBUG

                    section("Open a link")
                    openLink

                    section("Website pages (in-app browser)")
                    ForEach(WebsitePage.allCases, id: \.self) { page in
                        ListRow(label: page.rawValue, showsChevron: true) { router.openWebsite(page) }
                    }

                    section("Upload a test photo")
                    uploadTest

                    section("Caches")
                    ListRow(label: "Empty the image caches", leadingIcon: .trash) { ImageLoading.clearCaches() }
                    ListRow(label: "Delete the catalog copies", leadingIcon: .trash) { CatalogDiskCache().clear() }
                    #endif
                }
                .padding(.bottom, TaleedSpacing.s24)
            }
        }
        // Debug copy: left to right whatever the app language.
        .environment(\.layoutDirection, .leftToRight)
    }

    private var simulateShipment: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            TaleedTextField(label: "Order ID", text: $orderId, placeholder: "cmveh…")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            ForEach(ShipmentSimulationStep.allCases, id: \.self) { option in
                TaleedRadio(title: option.rawValue, isSelected: step == option) { step = option }
            }
            if let simulationResult {
                InlineAlert(kind: simulationResult.kind, title: simulationResult.text)
            }
            HStack(spacing: TaleedSpacing.s12) {
                TaleedButton(title: "Simulate", kind: .secondary, size: .medium, isLoading: isSimulating) {
                    Task { await simulate() }
                }
                .disabled(orderId.trimmingCharacters(in: .whitespaces).isEmpty || developmentApi == nil)
                TaleedButton(title: "Open the order", kind: .outline, size: .medium) {
                    router.open(.screen(.order(id: orderId.trimmingCharacters(in: .whitespaces))))
                }
                .disabled(orderId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }

    private var openLink: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            TaleedTextField(label: "Link or path", text: $link, placeholder: "/listings/… or https://taleed.app/…")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            if !link.isEmpty {
                Text(verbatim: String(describing: LinkRouter.destination(for: link)))
                    .taleedFont(TaleedFont.bodyRegular)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
            }
            TaleedButton(title: "Open", kind: .secondary, size: .medium) {
                router.open(LinkRouter.destination(for: link))
            }
            .disabled(link.isEmpty)
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }

    private var uploadTest: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            if let upload {
                HStack(spacing: TaleedSpacing.s12) {
                    RemoteImage(url: upload.thumbURL)
                        .frame(width: 64, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: TaleedRadius.s))
                    Text(verbatim: upload.key)
                        .taleedFont(TaleedFont.bodyRegular)
                        .foregroundStyle(TaleedColor.textSecondarySmall)
                        .accessibilityIdentifier("upload_key")
                }
            }
            if let uploadError {
                InlineAlert(kind: .error, title: uploadError)
            }
            TaleedButton(title: "Upload (listing_photo)", kind: .secondary, size: .medium, isLoading: isUploading) {
                Task { await uploadTestPhoto() }
            }
            .disabled(developmentApi == nil || !session.isSignedIn)
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }

    /// A 3000 × 2000 picture through `PhotoUploadService`: scaled to 1200 wide, JPEG, multipart.
    private func uploadTestPhoto() async {
        guard let developmentApi else { return }
        isUploading = true
        uploadError = nil
        defer { isUploading = false }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format).image { context in
            UIColor(TaleedColor.brandPrimary).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
            UIColor.white.setFill()
            context.fill(CGRect(x: 1000, y: 500, width: 1000, height: 1000))
        }
        do {
            upload = try await PhotoUploadService(api: developmentApi).upload(image, purpose: .listingPhoto)
        } catch {
            uploadError = "\(l10n.message(for: error)) (\(error.code?.rawValue ?? "-"))"
        }
    }

    private func section(_ title: String) -> some View {
        Eyebrow(text: title)
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.top, TaleedSpacing.s24)
            .padding(.bottom, TaleedSpacing.s8)
    }

    private func simulate() async {
        guard let developmentApi else { return }
        isSimulating = true
        defer { isSimulating = false }
        do {
            try await developmentApi.simulateShipment(orderId: orderId.trimmingCharacters(in: .whitespaces), step: step)
            simulationResult = (.success, "Done: \(step.rawValue). Reload the order.")
        } catch {
            let code = error.code.map { $0.rawValue } ?? "status \(error.status.map(String.init) ?? "none")"
            simulationResult = (.error, "\(l10n.message(for: error)) (\(code))")
        }
    }
}

private struct DevelopmentApiKey: EnvironmentKey {
    static var defaultValue: (any DevelopmentApi & UploadsApi)? { nil }
}

extension EnvironmentValues {
    /// The development-only calls, for the developer menu.
    var developmentApi: (any DevelopmentApi & UploadsApi)? {
        get { self[DevelopmentApiKey.self] }
        set { self[DevelopmentApiKey.self] = newValue }
    }
}
#endif
