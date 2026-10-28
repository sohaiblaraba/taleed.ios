import SafariServices
import UIKit

/// Opens website pages (terms, privacy, buyer protection, guides: `GET /config` `links`) in
/// `SFSafariViewController` over the app (app-guidelines, Website pages). Payment pages use
/// `ASWebAuthenticationSession` instead (slice D).
@MainActor
enum InAppBrowser {
    static func open(_ url: URL) {
        guard let presenter = topViewController() else { return }
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        let safari = SFSafariViewController(url: url, configuration: configuration)
        // The Appearance setting, read from the stored choice (AppearanceManager), not from the presenter:
        // the browser's bars follow it even when the presenter's traits lag behind the window's.
        let style = AppearanceManager.storedAppearance().userInterfaceStyle
        let traits = UITraitCollection(userInterfaceStyle: style)
        safari.overrideUserInterfaceStyle = style
        // iOS 17 to 25 tint the bars (`surfaceElevated`). iOS 26 ignores both tints (deprecated): its glass
        // bars follow the page under them, and the website has no dark theme.
        safari.preferredControlTintColor = UIColor(TaleedColor.brandPrimary).resolvedColor(with: traits)
        safari.preferredBarTintColor = UIColor(TaleedColor.surfaceElevated).resolvedColor(with: traits)
        safari.dismissButtonStyle = .close
        safari.modalPresentationStyle = .pageSheet
        presenter.present(safari, animated: true)
    }

    /// The view controller on top, so the browser (or Google's sign-in page) also opens over a sheet.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
