import SwiftUI
import FinderCoreFFI

@main
struct MySearchBuddyApp: App {
    @StateObject private var bookmarkStore = BookmarkStore()
    @StateObject private var coverageSettings = ContentCoverageSettings()
    @StateObject private var purchaseManager = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bookmarkStore)
                .environmentObject(coverageSettings)
                .environmentObject(purchaseManager)
        }
        .commands {
            QuickLookCommands()
        }
        Settings {
            SettingsView()
                .environmentObject(coverageSettings)
        }
    }
}
