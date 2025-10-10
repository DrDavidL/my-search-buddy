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
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentSize)
        .commands {
            AboutCommands()
            QuickLookCommands()
            FileCommands()
            HelpCommands()

            // File menu - New Window command
            CommandGroup(replacing: .newItem) {
                NewWindowButton()
            }

            // Window menu - reopen main window
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

// Helper view to create a new window using SwiftUI's openWindow action
struct NewWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Window") {
            NSLog("[NewWindowButton] Opening new window")
            openWindow(id: "main")
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}
