import Foundation
import AppKit
import os.log

final class BookmarkStore: ObservableObject {
    @Published var urls: [URL] = []
    private let key = "bookmarks.v1"

    init() {
        load()
    }

    func add(url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        var list = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        list.append(data)
        UserDefaults.standard.set(list, forKey: key)
        load()
    }

    func remove(at offsets: IndexSet) {
        var list = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        for index in offsets.sorted(by: >) {
            guard list.indices.contains(index) else { continue }
            list.remove(at: index)
        }
        UserDefaults.standard.set(list, forKey: key)
        load()
    }

    private func load() {
        let datas = (UserDefaults.standard.array(forKey: key) as? [Data]) ?? []
        urls = datas.compactMap { data in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: [.withSecurityScope],
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &isStale) else {
                os_log("Failed to resolve bookmark")
                return nil
            }
            return url
        }
    }
}

func pickFolder(onPicked: (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Add"
    if panel.runModal() == .OK, let url = panel.urls.first {
        onPicked(url)
    }
}
