import AppKit
import QuickLookUI

private final class QuickLookCoordinator: NSResponder, QLPreviewPanelDelegate, QLPreviewPanelDataSource {
    static let shared = QuickLookCoordinator()

    private struct ScopedPreviewItem {
        let url: URL
        let stopAccess: (() -> Void)?
    }

    private var items: [ScopedPreviewItem] = []
    private weak var previousResponder: NSResponder?

    func present(paths: [String], using bookmarkStore: BookmarkStore) {
        releaseScopedAccess()

        var inaccessible: [String] = []
        items = paths.compactMap { path in
            if let scoped = bookmarkStore.scopedURL(forAbsolutePath: path) {
                return ScopedPreviewItem(url: scoped.url, stopAccess: scoped.stopAccess)
            }
            inaccessible.append(path)
            return nil
        }

        guard !items.isEmpty else {
            if !inaccessible.isEmpty {
                presentAccessAlert(for: inaccessible)
            }
            return
        }
        guard let panel = QLPreviewPanel.shared(), let window = NSApp.keyWindow else {
            releaseScopedAccess()
            return
        }

        previousResponder = window.nextResponder
        window.nextResponder = self
        panel.makeKeyAndOrderFront(nil)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.delegate = self
        panel.dataSource = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        releaseScopedAccess()
        items.removeAll()
        panel.delegate = nil
        panel.dataSource = nil
        if let window = NSApp.keyWindow, window.nextResponder === self {
            window.nextResponder = previousResponder
        }
        previousResponder = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        items[index].url as NSURL
    }

    private func releaseScopedAccess() {
        for item in items {
            item.stopAccess?()
        }
        items.removeAll()
    }

    private func presentAccessAlert(for paths: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Cannot Preview File"
        if paths.count == 1, let path = paths.first {
            alert.informativeText = "Quick Look doesn't have permission to preview \(path). Add its parent folder under Locations first."
        } else {
            alert.informativeText = "Quick Look doesn't have permission to preview the selected files. Add their folders under Locations first."
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

func quickLook(path: String, bookmarkStore: BookmarkStore) {
    QuickLookCoordinator.shared.present(paths: [path], using: bookmarkStore)
}

func quickLook(paths: [String], bookmarkStore: BookmarkStore) {
    QuickLookCoordinator.shared.present(paths: paths, using: bookmarkStore)
}

func revealInFinder(path: String) {
    let url = URL(fileURLWithPath: path)
    let hadAccess = url.startAccessingSecurityScopedResource()
    NSWorkspace.shared.activateFileViewerSelecting([url])
    if hadAccess {
        url.stopAccessingSecurityScopedResource()
    }
}
