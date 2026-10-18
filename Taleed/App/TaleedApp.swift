import SwiftUI

@main
struct TaleedApp: App {
    /// Nil when unit tests host the app, so that the tests make no API calls.
    @State private var container: AppContainer? = Self.isRunningUnitTests ? nil : AppContainer()

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
