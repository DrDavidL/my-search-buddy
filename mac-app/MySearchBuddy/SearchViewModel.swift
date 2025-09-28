import Foundation
import FinderCoreFFI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var scope: FinderCore.Scope = .both
    @Published private(set) var results: [FinderCore.Hit] = []
    @Published private(set) var isSearching = false

    var sort: SortOption = .score
    var activeRootPaths: [String] = []

    private var searchTask: Task<Void, Never>?
    private let searchExecutor = FinderCoreSearchExecutor()

    func runSearch(limit: Int? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            isSearching = false
            return
        }

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            await self.performSearch(term: trimmed, scope: self.scope, limit: limit)
        }
    }

    func clear() {
        searchTask?.cancel()
        results = []
        query = ""
    }

    private func performSearch(term: String, scope: FinderCore.Scope, limit: Int?) async {
        isSearching = true
        let currentSort = sort
        let resultLimit = limit ?? 200
        let hits = await searchExecutor.search(
            term: term,
            scope: scope,
            limit: resultLimit,
            sortByModifiedDescending: currentSort == .modified
        )
        guard !Task.isCancelled else {
            isSearching = false
            return
        }
        let filtered = filterHits(hits)
        results = Array(filtered.prefix(resultLimit))
        isSearching = false
    }

    private func filterHits(_ hits: [FinderCore.Hit]) -> [FinderCore.Hit] {
        guard !activeRootPaths.isEmpty else { return hits }
        return hits.filter { hit in
            activeRootPaths.contains { hit.path.hasPrefix($0) }
        }
    }
}

enum SortOption: Hashable {
    case score
    case modified
}

actor FinderCoreSearchExecutor {
    func search(
        term: String,
        scope: FinderCore.Scope,
        limit: Int,
        sortByModifiedDescending: Bool
    ) -> [FinderCore.Hit] {
        FinderCore.search(
            term,
            scope: scope,
            limit: Int32(limit),
            sortByModifiedDescending: sortByModifiedDescending
        )
    }
}
