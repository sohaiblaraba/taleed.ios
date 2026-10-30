import SwiftUI

@main
struct TaleedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Nil when unit tests host the app, so that the tests make no API calls.
    @State private var container: AppContainer?

    init() {
        if !Self.isRunningUnitTests {
            // Before the app's objects, which take the push token source and Crashlytics from it.
            FirebaseServices.configure()
            // Before launch ends, so the tap that launched the app reaches the router (slice C, Opening a push).
            PushNotificationCenter.shared.install()
        }
        _container = State(initialValue: Self.isRunningUnitTests ? nil : AppContainer())
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                AppRootView(container: container)
            }
        }
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
