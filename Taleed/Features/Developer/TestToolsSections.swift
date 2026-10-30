#if DEBUG || TALEED_TEST_TOOLS
import SwiftUI
import UIKit

/// "Send test notifications" (slice J): `POST /dev/notifications/test` with `{"all": true}`, or one type picked
/// from `GET /dev/notifications/types`, then the `created` and `skipped` lists. A created row opens its `url`
/// through the router, as a tap on its push does. Debug and Staging builds only; English only.
struct TestNotificationsSection: View {
    let api: any DevelopmentApi
    @Environment(AppRouter.self) private var router
    @Environment(SessionManager.self) private var session
    @Environment(LanguageManager.self) private var l10n

    @State private var types: [TestNotificationType] = []
    @State private var pickedType = ""
    @State private var isLoadingTypes = false
    @State private var isSending = false
    @State private var result: TestNotificationResult?
    @State private var error: String?
    @State private var showsSkipped = false

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
            Text(verbatim: "Creates notifications for the signed-in member through the real code: stored, pushed to "
                + "this account's devices in their language, emailed when the type is. Each tap creates new ones.")
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textSecondarySmall)
            TaleedButton(title: "Send all types", kind: .secondary, size: .medium, isLoading: isSending && pickedType.isEmpty) {
                Task { await send(type: nil) }
            }
            .disabled(!session.isSignedIn || isSending)
            .accessibilityIdentifier("testTools.sendAll")
            typePicker
            if let error {
                InlineAlert(kind: .error, title: error)
            }
            if let result {
                results(result)
            }
        }
        .padding(.horizontal, TaleedLayout.screenMargin)
    }

    @ViewBuilder
    private var typePicker: some View {
        if types.isEmpty {
            TaleedButton(title: "Pick one type…", kind: .outline, size: .medium, isLoading: isLoadingTypes) {
                Task { await loadTypes() }
            }
            .disabled(!session.isSignedIn || isLoadingTypes)
        } else {
            Picker(selection: $pickedType) {
                Text(verbatim: "Choose a type").tag("")
                ForEach(types) { type in
                    Text(verbatim: label(type)).tag(type.type)
                }
            } label: {
                Text(verbatim: "Type")
            }
            .pickerStyle(.menu)
            TaleedButton(title: pickedType.isEmpty ? "Send this type" : "Send \(pickedType)", kind: .secondary,
                         size: .medium, isLoading: isSending && !pickedType.isEmpty) {
                Task { await send(type: pickedType) }
            }
            .disabled(pickedType.isEmpty || isSending)
        }
    }

    private func results(_ result: TestNotificationResult) -> some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s8) {
            InlineAlert(kind: .success, title: "Created \(result.created.count), skipped \(result.skipped.count)")
                .accessibilityIdentifier("testTools.result")
            Eyebrow(text: "Created (newest last)")
            ForEach(Array(result.created.enumerated()), id: \.offset) { _, created in
                Button {
                    router.open(LinkRouter.destination(for: created.url))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: created.type + (created.push ? "" : " · no push") + (created.fallback ? " · fallback" : ""))
                            .taleedFont(TaleedFont.cardTitle)
                            .foregroundStyle(TaleedColor.textPrimary)
                        Text(verbatim: path(created.url))
                            .taleedFont(TaleedFont.bodyRegular)
                            .foregroundStyle(TaleedColor.textSecondarySmall)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            if !result.skipped.isEmpty {
                TaleedButton(title: showsSkipped ? "Hide skipped" : "Show skipped (\(result.skipped.count))", kind: .outline,
                             size: .medium) { showsSkipped.toggle() }
                if showsSkipped {
                    ForEach(result.skipped) { skipped in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: skipped.type)
                                .taleedFont(TaleedFont.cardTitle)
                                .foregroundStyle(TaleedColor.textPrimary)
                            Text(verbatim: skipped.reason)
                                .taleedFont(TaleedFont.bodyRegular)
                                .foregroundStyle(TaleedColor.textSecondarySmall)
                        }
                    }
                }
            }
        }
    }

    private func label(_ type: TestNotificationType) -> String {
        var parts = [type.type]
        if type.audience != "member" { parts.append(type.audience) }
        if !type.inUse { parts.append("legacy") }
        if !type.push { parts.append("no push") }
        return parts.joined(separator: " · ")
    }

    /// The link without the scheme and host, which are the same for every row.
    private func path(_ url: String) -> String {
        guard let components = URLComponents(string: url), components.host != nil else { return url }
        return components.path + (components.query.map { "?\($0)" } ?? "")
    }

    private func loadTypes() async {
        isLoadingTypes = true
        defer { isLoadingTypes = false }
        do {
            types = try await api.testNotificationTypes()
            error = nil
        } catch {
            self.error = describe(error)
        }
    }

    private func send(type: String?) async {
        isSending = true
        defer { isSending = false }
        do {
            result = try await api.sendTestNotifications(type: type)
            showsSkipped = false
            error = nil
        } catch {
            self.error = describe(error)
        }
    }

    private func describe(_ error: ApiError) -> String {
        let code = error.code.map { $0.rawValue } ?? "status \(error.status.map(String.init) ?? "none")"
        return "\(l10n.message(for: error)) (\(code))"
    }
}

/// Firebase's state in this build, the push token, and "Test crash" (slice J): a deliberate crash, so that
/// the first Crashlytics report arrives. The report leaves on the next launch, when this build sends crash
/// reports (Release and Staging; Debug keeps them on the device).
struct CrashTestSection: View {
    @State private var tokenState: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListRow(label: "Firebase", trailingText: FirebaseServices.isConfigured ? "Set up" : "No GoogleService-Info.plist")
            ListRow(label: "Crash reports sent", trailingText: FirebaseServices.isConfigured && CrashReporting.isCollectionEnabled()
                ? "Yes" : "No")
            ListRow(label: tokenState ?? "Copy the push token", leadingIcon: .copy) {
                Task { await copyToken() }
            }
            .disabled(FirebaseServices.pushTokens == nil)
            TaleedButton(title: "Test crash", kind: .secondary, size: .medium) {
                fatalError("Test crash from the test tools (slice J)")
            }
            .padding(.horizontal, TaleedLayout.screenMargin)
            .padding(.top, TaleedSpacing.s8)
            .accessibilityIdentifier("testTools.crash")
        }
    }

    private func copyToken() async {
        guard let source = FirebaseServices.pushTokens else { return }
        tokenState = "Fetching the token…"
        if let token = await source.registrationToken() {
            UIPasteboard.general.string = token
            tokenState = "Copied: \(token.prefix(12))…"
        } else {
            tokenState = "No token (permission or APNs missing)"
        }
    }
}
#endif
