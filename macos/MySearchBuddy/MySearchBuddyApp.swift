import SwiftUI
import FinderCoreFFI

@main
struct MySearchBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSLog("[App] MySearchBuddyApp initializing")
    }

    @StateObject private var bookmarkStore = BookmarkStore()
    @StateObject private var coverageSettings = ContentCoverageSettings()
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var indexCoordinator = IndexCoordinator()
    @StateObject private var fileTypeFilters = FileTypeFilters()

    var body: some Scene {
        WindowGroup(id: "main") {
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

            // Add main window to Window menu for reopening
            CommandGroup(after: .windowList) {
                Divider()
                Button("Main Window") {
                    AppDelegate.showMainWindow()
                }
                .keyboardShortcut("1", modifiers: .command)
            }
        }
        Settings {
            SettingsView()
                .environmentObject(coverageSettings)
                .environmentObject(indexCoordinator)
                .environmentObject(fileTypeFilters)
        }
    }
}
