import Foundation
import SwiftUI

/// The consent step before Taleed sends personal data to an AI service (slice I; Apple 5.1.2(i)): the
/// service's name as the title, what is sent and why, an optional hint under it, then the two answers.
/// Identity verification (OpenAI) and photo search (Jina AI) use it inside a design-system bottom sheet.
struct AiConsentContent: View {
    let message: String
    var hint: String?
    let agreeTitle: String
    let declineTitle: String
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TaleedSpacing.s16) {
            Text(message)
                .taleedFont(TaleedFont.bodyRegular)
                .foregroundStyle(TaleedColor.textBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("aiConsent.body")
            if let hint {
                Text(hint)
                    .taleedFont(TaleedFont.bodySmall)
                    .foregroundStyle(TaleedColor.textSecondarySmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("aiConsent.hint")
            }
            VStack(spacing: TaleedSpacing.s12) {
                TaleedButton(title: agreeTitle, kind: .secondary, size: .large, isFullWidth: true, action: onAgree)
                    .accessibilityIdentifier("aiConsent.agree")
                TaleedButton(title: declineTitle, kind: .outline, size: .large, isFullWidth: true, action: onDecline)
                    .accessibilityIdentifier("aiConsent.decline")
            }
            .padding(.top, TaleedSpacing.s4)
        }
    }
}

/// The member's answer to the photo search consent, kept on this device per account (slice I, Photo
/// search): a signed-out visitor has one shared "guest" entry. The website keeps the same answer in
/// `localStorage` under `taleed:photo-search-consent:<userId|guest>`.
@MainActor
final class PhotoSearchConsentStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `taleed.photoSearchConsent.<userId|guest>`.
    nonisolated static func key(for userId: String?) -> String {
        "taleed.photoSearchConsent." + (userId ?? "guest")
    }

    func hasConsent(userId: String?) -> Bool {
        defaults.bool(forKey: Self.key(for: userId))
    }

    /// "Agree": searches by photo from now on without asking.
    func agree(userId: String?) {
        defaults.set(true, forKey: Self.key(for: userId))
    }

    /// `400 ai_consent_required`: the server does not have the consent, so the step shows again.
    func forget(userId: String?) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }
}
