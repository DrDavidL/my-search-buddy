import SwiftUI
import FinderCoreFFI

@main
struct MacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    private let dylibPath = FinderCoreFFI.defaultLibraryPath()

    var body: some View {
        Text("My Search Buddy")
            .frame(minWidth: 320, minHeight: 200)
            .accessibilityIdentifier(dylibPath)
    }
}
