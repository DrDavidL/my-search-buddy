import AppKit
import QuickLookUI

private final class QuickLookController: NSObject, QLPreviewPanelDelegate, QLPreviewPanelDataSource {
    static let shared = QuickLookController()

    private var items: [URL] = []
    private var scopedAccess: [URL: Bool] = [:]

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

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.delegate = self
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
    }

    func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {}

    func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        releaseScopedAccess()
        items.removeAll()
        panel.delegate = nil
        panel.dataSource = nil
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
    QuickLookController.shared.present(paths: [path])
}

func quickLook(paths: [String]) {
    QuickLookController.shared.present(paths: paths)
}

func revealInFinder(path: String) {
    let url = URL(fileURLWithPath: path)
    let hadAccess = url.startAccessingSecurityScopedResource()
    NSWorkspace.shared.activateFileViewerSelecting([url])
    if hadAccess {
        url.stopAccessingSecurityScopedResource()
    }
}
