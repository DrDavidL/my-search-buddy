import SwiftUI
import FinderCoreFFI

@main
struct MySearchBuddyApp: App {
    init() {
        NSLog("[App] MySearchBuddyApp initializing")
    }

    @StateObject private var bookmarkStore = BookmarkStore()
    @StateObject private var coverageSettings = ContentCoverageSettings()
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var indexCoordinator = IndexCoordinator()
    @StateObject private var fileTypeFilters = FileTypeFilters()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bookmarkStore)
                .environmentObject(coverageSettings)
                .environmentObject(purchaseManager)
                .environmentObject(indexCoordinator)
                .environmentObject(fileTypeFilters)
        }
        .commands {
            AboutCommands()
            QuickLookCommands()
            FileCommands()
            HelpCommands()
        }
        Settings {
            SettingsView()
                .environmentObject(coverageSettings)
                .environmentObject(indexCoordinator)
                .environmentObject(fileTypeFilters)
        }
    }
}
