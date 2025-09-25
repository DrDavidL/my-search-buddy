import Foundation
import FinderCoreFFI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var scope: FinderCore.Scope = .both
    @Published private(set) var results: [FinderCore.Hit] = []
    @Published private(set) var isSearching = false
    var sort: SortOption = .score

    private var searchTask: Task<Void, Never>?

    func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            return
        }

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            await self.performSearch(term: trimmed, scope: self.scope)
        }
    }

    func clear() {
        searchTask?.cancel()
        results = []
        query = ""
    }

    private func performSearch(term: String, scope: FinderCore.Scope) async {
        isSearching = true
        let hits = await Task.detached(priority: .userInitiated) {
            FinderCore.search(term, scope: scope, limit: 200, sortByModifiedDescending: sort == .modified)
        }.value
        guard !Task.isCancelled else { return }
        results = hits
        isSearching = false
    }
}

enum SortOption: Hashable {
    case score
    case modified
}
