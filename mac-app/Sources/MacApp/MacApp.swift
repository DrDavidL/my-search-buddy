import SwiftUI

@main
struct MacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("My Search Buddy")
            .frame(minWidth: 320, minHeight: 200)
    }
}
