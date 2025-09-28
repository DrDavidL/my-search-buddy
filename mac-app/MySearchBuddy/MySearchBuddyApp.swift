import SwiftUI
import FinderCoreFFI

@main
struct MySearchBuddyApp: App {
    @StateObject private var bookmarkStore = BookmarkStore()
    @StateObject private var coverageSettings = ContentCoverageSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bookmarkStore)
                .environmentObject(coverageSettings)
        }
        Settings {
            SettingsView()
                .environmentObject(coverageSettings)
        }
    }
}
