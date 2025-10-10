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
    var allBookmarkURLs: [URL] {
        bookmarks.map { $0.url }
    }
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

            var scopedURL = root
            let lastIndex = targetComponents.count - 1
            for index in rootComponents.count..<targetComponents.count {
                let component = targetComponents[index]
                let isDirectoryComponent = index < lastIndex
                scopedURL.appendPathComponent(component, isDirectory: isDirectoryComponent)
            }

            let finalURL = scopedURL
            let hasFileScope = finalURL.startAccessingSecurityScopedResource()

            return ScopedURL(
                url: finalURL,
                stopAccess: { [root] in
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
        NSLog("[BookmarkStore] Initializing BookmarkStore")
        load()
        NSLog("[BookmarkStore] Loaded %d bookmarks", bookmarks.count)
    }

    func add(url: URL) throws {
        NSLog("[BookmarkStore] Adding bookmark for: %@", url.path)
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        var list = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        list.append(data)
        UserDefaults.standard.set(list, forKey: key)
        load()
        NSLog("[BookmarkStore] Now have %d bookmarks", bookmarks.count)
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
        NSLog("[BookmarkStore] Loading %d bookmark data entries", datas.count)
        let resolved = datas.compactMap { data -> URL? in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: [.withSecurityScope],
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &isStale) else {
                NSLog("[BookmarkStore] Failed to resolve a bookmark")
                os_log("Failed to resolve bookmark")
                return nil
            }
            NSLog("[BookmarkStore] Resolved bookmark: %@", url.path)
            return url
        }
        bookmarks = resolved.map { url in
            Bookmark(id: UUID(), url: url, isEnabled: true)
        }
        NSLog("[BookmarkStore] Final bookmark count: %d", bookmarks.count)
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

// MARK: - File Type Filters

struct FileTypeFilter: Codable, Identifiable {
    let id: String
    var name: String
    var extensions: [String]
    var icon: String

    var queryString: String {
        extensions.map { "ext:\($0)" }.joined(separator: " OR ")
    }
}

@MainActor
final class FileTypeFilters: ObservableObject {
    @Published var filters: [FileTypeFilter] = []

    private let userDefaultsKey = "fileTypeFilters_v2"  // Changed to v2 to force reload of new filters

    init() {
        loadFilters()
    }

    private func loadFilters() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([FileTypeFilter].self, from: data) {
            filters = decoded
        } else {
            // Default filters
            filters = [
                FileTypeFilter(
                    id: "alloffice",
                    name: "All Office",
                    extensions: ["doc", "docx", "ppt", "pptx", "xls", "xlsx", "pdf"],
                    icon: "doc.text"
                ),
                FileTypeFilter(
                    id: "doc",
                    name: "DOC",
                    extensions: ["doc", "docx"],
                    icon: "doc.richtext"
                ),
                FileTypeFilter(
                    id: "pdf",
                    name: "PDF",
                    extensions: ["pdf"],
                    icon: "doc.fill"
                ),
                FileTypeFilter(
                    id: "xls",
                    name: "XLS",
                    extensions: ["xls", "xlsx"],
                    icon: "tablecells"
                ),
                FileTypeFilter(
                    id: "ppt",
                    name: "PPT",
                    extensions: ["ppt", "pptx"],
                    icon: "rectangle.on.rectangle"
                ),
                FileTypeFilter(
                    id: "code",
                    name: "Code",
                    extensions: ["swift", "py", "js", "ts", "tsx", "jsx", "c", "cpp", "h", "m", "java", "go", "rs", "rb", "php"],
                    icon: "chevron.left.forwardslash.chevron.right"
                ),
                FileTypeFilter(
                    id: "images",
                    name: "Images",
                    extensions: ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp", "heic"],
                    icon: "photo"
                ),
                FileTypeFilter(
                    id: "videos",
                    name: "Videos",
                    extensions: ["mp4", "mov", "avi", "mkv", "webm", "m4v", "flv"],
                    icon: "film"
                ),
                FileTypeFilter(
                    id: "custom",
                    name: "Custom",
                    extensions: ["txt", "md", "rtf", "csv", "json", "xml", "yml", "yaml"],
                    icon: "slider.horizontal.3"
                )
            ]
            saveFilters()
        }
    }

    func saveFilters() {
        if let encoded = try? JSONEncoder().encode(filters) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    func updateFilter(id: String, extensions: [String]) {
        if let index = filters.firstIndex(where: { $0.id == id }) {
            filters[index].extensions = extensions
            saveFilters()
        }
    }

    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        loadFilters()
    }
}
