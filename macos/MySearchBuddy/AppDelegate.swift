import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when the last window is closed - allow background indexing to continue
        NSLog("[AppDelegate] Window closed but keeping app running for background indexing")
        return false
    }

    static func showMainWindow() {
        NSLog("[AppDelegate] Showing main window")
        NSApp.activate(ignoringOtherApps: true)

        // Find any existing window (visible or not)
        // SwiftUI WindowGroup windows persist when closed, they're just hidden
        if let window = NSApp.windows.first(where: { window in
            // Find the main app window (exclude Settings windows)
            !window.title.contains("Settings")
        }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSLog("[AppDelegate] Brought window to front")
        } else {
            // No window found - user should use File > New Window (Cmd+N)
            NSLog("[AppDelegate] No window found - use File > New Window to create one")
        }
    }
}
