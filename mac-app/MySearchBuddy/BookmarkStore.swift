import Foundation
import AppKit
import os.log

final class BookmarkStore: ObservableObject {
    struct Bookmark: Identifiable, Hashable {
        let id: UUID
        let url: URL
        var isEnabled: Bool
    }

    @Published var bookmarks: [Bookmark] = []
    var enabledURLs: [URL] {
        bookmarks.filter { $0.isEnabled }.map { $0.url }
    }
    @Published var urls: [URL] = []
    private let key = "bookmarks.v1"

    struct ScopedURL {
        let url: URL
        let stopAccess: () -> Void
    }

    func scopedURL(forAbsolutePath path: String) -> ScopedURL? {
        let target = URL(fileURLWithPath: path).standardizedFileURL
        let activeBookmarks = bookmarks.filter { $0.isEnabled }

        for bookmark in activeBookmarks {
            let root = bookmark.url
            let rootStandardized = root.standardizedFileURL
            let rootComponents = rootStandardized.pathComponents
            let targetComponents = target.pathComponents

            guard targetComponents.count >= rootComponents.count else { continue }

            var isDescendant = true
            for (index, component) in rootComponents.enumerated() {
                if component != targetComponents[index] {
                    isDescendant = false
                    break
                }
            }

            guard isDescendant else { continue }
            guard root.startAccessingSecurityScopedResource() else { continue }

            let relativeComponents = Array(targetComponents.dropFirst(rootComponents.count))
            var scopedURL = root
            for (index, component) in relativeComponents.enumerated() {
                let isDirectoryComponent = index < relativeComponents.count - 1
                scopedURL.appendPathComponent(component, isDirectory: isDirectoryComponent)
            }

            let finalURL = scopedURL
            let hasFileScope = finalURL.startAccessingSecurityScopedResource()

            return ScopedURL(
                url: finalURL,
                stopAccess: {
                    if hasFileScope {
                        finalURL.stopAccessingSecurityScopedResource()
                    }
                    root.stopAccessingSecurityScopedResource()
                }
            )
        }

        return nil
    }

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
        let resolved = datas.compactMap { data -> URL? in
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
        urls = resolved
        bookmarks = resolved.map { url in
            Bookmark(id: UUID(), url: url, isEnabled: true)
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
