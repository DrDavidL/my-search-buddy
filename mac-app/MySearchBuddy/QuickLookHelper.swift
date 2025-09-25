import AppKit
import QuickLookUI

func revealInFinder(path: String) {
    let url = URL(fileURLWithPath: path)
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

private final class PreviewDataSource: NSObject, QLPreviewPanelDataSource {
    var items: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        items[index] as NSURL
    }
}

private let dataSource = PreviewDataSource()

func quickLook(path: String) {
    let url = URL(fileURLWithPath: path)
    dataSource.items = [url]
    if let panel = QLPreviewPanel.shared() {
        panel.dataSource = dataSource
        panel.makeKeyAndOrderFront(nil)
    }
}
