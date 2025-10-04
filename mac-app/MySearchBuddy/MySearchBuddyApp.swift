import SwiftUI
import FinderCoreFFI

@main
struct MySearchBuddyApp: App {
    @StateObject private var bookmarkStore = BookmarkStore()
    @StateObject private var coverageSettings = ContentCoverageSettings()
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var indexCoordinator = IndexCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bookmarkStore)
                .environmentObject(coverageSettings)
                .environmentObject(purchaseManager)
                .environmentObject(indexCoordinator)
        }
        .commands {
            QuickLookCommands()
            FileCommands()
        }
        Settings {
            SettingsView()
                .environmentObject(coverageSettings)
                .environmentObject(indexCoordinator)
        }
    }
}
