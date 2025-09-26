import SwiftUI
import FinderCoreFFI

struct ContentView: View {
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @StateObject private var indexCoordinator = IndexCoordinator()
    @StateObject private var searchViewModel = SearchViewModel()

    @FocusState private var searchFieldIsFocused: Bool
    @State private var selectedResultPath: String?
    @State private var openSelection: FinderCore.Hit?
    @State private var sortBy = SortOption.score

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            locationListSection
            indexingControlsSection
            Divider()
            searchControlsSection
            resultsListSection
            actionButtons
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 480)
        .onAppear { searchFieldIsFocused = true }
        .onChange(of: searchViewModelResults) { hits in
            if let first = hits.first {
                selectedResultPath = first.path
            } else {
                selectedResultPath = nil
            }
        }
    }

    private var headerSection: some View {
        Text("My Search Buddy")
            .font(.largeTitle)
            .bold()
    }

    private var locationListSection: some View {
        Group {
            if bookmarkStore.urls.isEmpty {
                Text("Add a folder to begin indexing.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(Array(bookmarkStore.urls.enumerated()), id: \.offset) { index, url in
                        HStack {
                            Text(url.path)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.head)
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                bookmarkStore.remove(at: IndexSet(integer: index))
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this location")
                        }
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                bookmarkStore.remove(at: IndexSet(integer: index))
                            }
                        }
                    }
                }
                .frame(minHeight: 160)
            }
        }
    }

    private var indexingControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Add Location…", action: showPicker)
                Button(indexCoordinator.isIndexing ? "Cancel" : "Index Now", action: toggleIndexing)
                    .disabled(bookmarkStore.urls.isEmpty)
                Spacer()
            }
            Text(indexCoordinator.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var searchControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Search…", text: $searchViewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFieldIsFocused)
                    .onSubmit { searchViewModel.runSearch() }
                Button("Search") { searchViewModel.runSearch() }
                Button("Clear") { searchViewModel.clear() }
                    .disabled(searchViewModel.query.isEmpty)
            }

            Picker("Scope", selection: $searchViewModel.scope) {
                Text("Name").tag(FinderCore.Scope.name)
                Text("Content").tag(FinderCore.Scope.content)
                Text("Both").tag(FinderCore.Scope.both)
            }
            .pickerStyle(.segmented)
            .onChange(of: searchViewModel.scope) { _ in
                searchViewModel.runSearch()
            }

            Picker("Sort", selection: $sortBy) {
                Text("Score").tag(SortOption.score)
                Text("Modified").tag(SortOption.modified)
            }
            .pickerStyle(.segmented)
            .onChange(of: sortBy) { _ in
                searchViewModel.sort = sortBy
                searchViewModel.runSearch()
            }

            HStack(spacing: 8) {
                Text(resultSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if searchViewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
        }
    }

    private var resultsListSection: some View {
        List(selection: $selectedResultPath) {
            ForEach(searchViewModelResults, id: \.path) { hit in
                ResultRow(hit: hit)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedResultPath = hit.path }
                    .onTapGesture(count: 2) {
                        revealInFinder(path: hit.path)
                    }
            }
        }
        .listStyle(.inset)
        .frame(minHeight: 240)
    }

    private var actionButtons: some View {
        HStack {
            Button("Open in Finder", action: openSelected)
                .disabled(selectedHit == nil)
            Button("Quick Look", action: quickLookSelected)
                .disabled(selectedHit == nil)
            Spacer()
        }
    }

    private var searchViewModelResults: [FinderCore.Hit] {
        searchViewModel.results
    }

    private var selectedHit: FinderCore.Hit? {
        guard let selectedResultPath else { return nil }
        return searchViewModelResults.first { $0.path == selectedResultPath }
    }

    private var resultSummary: String {
        guard !searchViewModel.query.isEmpty else { return "" }
        let count = searchViewModelResults.count
        return "Results: \(count)"
    }

    private func showPicker() {
        pickFolder { url in
            do {
                try bookmarkStore.add(url: url)
            } catch {
                NSLog("Failed to save bookmark: %{public}@", error.localizedDescription)
            }
        }
    }

    private func toggleIndexing() {
        if indexCoordinator.isIndexing {
            indexCoordinator.cancel()
        } else {
            indexCoordinator.startIndexing(roots: bookmarkStore.urls)
        }
    }

    private func openSelected() {
        guard let hit = selectedHit else { return }
        revealInFinder(path: hit.path)
    }

    private func quickLookSelected() {
        guard let hit = selectedHit else { return }
        quickLook(path: hit.path)
    }
}

#Preview {
    ContentView()
        .environmentObject(BookmarkStore())
}
