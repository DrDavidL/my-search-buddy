import AppKit
import QuickLookUI

private final class QuickLookCoordinator: NSResponder, QLPreviewPanelDelegate, QLPreviewPanelDataSource {
    static let shared = QuickLookCoordinator()

    private var items: [URL] = []
    private var scopedAccess: [URL: Bool] = [:]
    private weak var previousResponder: NSResponder?

    func present(paths: [String]) {
        releaseScopedAccess()
        items = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            if url.startAccessingSecurityScopedResource() {
                scopedAccess[url] = true
            } else {
                scopedAccess[url] = false
            }
            return url
        }

        guard let panel = QLPreviewPanel.shared(), let window = NSApp.keyWindow else { return }

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
        items[index] as NSURL
    }

    private func releaseScopedAccess() {
        for (url, hadAccess) in scopedAccess where hadAccess {
            url.stopAccessingSecurityScopedResource()
        }
        scopedAccess.removeAll()
    }
}

func quickLook(path: String) {
    QuickLookCoordinator.shared.present(paths: [path])
}

func quickLook(paths: [String]) {
    QuickLookCoordinator.shared.present(paths: paths)
}

func revealInFinder(path: String) {
    let url = URL(fileURLWithPath: path)
    let hadAccess = url.startAccessingSecurityScopedResource()
    NSWorkspace.shared.activateFileViewerSelecting([url])
    if hadAccess {
        url.stopAccessingSecurityScopedResource()
    }
}
