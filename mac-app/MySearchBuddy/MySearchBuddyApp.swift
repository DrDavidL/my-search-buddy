import SwiftUI
import FinderCoreFFI

@main
struct MySearchBuddyApp: App {
    @StateObject private var bookmarkStore = BookmarkStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bookmarkStore)
        }
    }
}
