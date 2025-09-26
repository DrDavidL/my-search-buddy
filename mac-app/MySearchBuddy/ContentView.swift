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
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                locationListSection
                indexingControlsSection
                Divider()
                locationFiltersSection
                Divider()
                quickFiltersSection
                Spacer()
            }
            .frame(width: 380)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                searchControlsSection
                resultsListSection
                actionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 560)
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
                    ForEach(Array(bookmarkStore.bookmarks.enumerated()), id: \.offset) { index, bookmark in
                        HStack {
                            Text(bookmark.url.path)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.head)
                                .textSelection(.enabled)
                            Spacer()
                            Toggle("", isOn: bindingForBookmark(at: index))
                                .labelsHidden()
                                .toggleStyle(.switch)
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
            Text(statusSummary)
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

    private var quickFiltersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Filters")
                .font(.headline)
            HStack {
                quickFilterButton(title: "DOC", query: "ext:doc OR ext:docx")
                quickFilterButton(title: "PPT", query: "ext:ppt OR ext:pptx")
                quickFilterButton(title: "PDF", query: "ext:pdf")
                Spacer()
            }
        }
    }

    private func quickFilterButton(title: String, query: String) -> some View {
        Button(title) {
            searchViewModel.query = query
            searchViewModel.runSearch()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func openSelected() {
        guard let hit = selectedHit else { return }
        revealInFinder(path: hit.path)
    }

    private func quickLookSelected() {
        guard let hit = selectedHit else { return }
        quickLook(path: hit.path)
    }

    private func bindingForBookmark(at index: Int) -> Binding<Bool> {
        Binding(
            get: { bookmarkStore.bookmarks[index].isEnabled },
            set: { newValue in
                bookmarkStore.bookmarks[index].isEnabled = newValue
            }
        )
    }

    private func runFilteredSearch() {
        let enabledPaths = bookmarkStore.bookmarks.filter { $0.isEnabled }.map { $0.url.path }
        if enabledPaths.isEmpty {
            searchViewModel.runSearch(using: "")
        } else {
            let clauses = enabledPaths.map { "path:\($0)/*" }
            let filterQuery = clauses.joined(separator: " OR ")
            searchViewModel.runSearch(using: filterQuery)
        }
    }

    private var statusSummary: String {
        if let indexed = indexCoordinator.lastIndexDate {
            let formatter = RelativeDateTimeFormatter()
            let relative = formatter.localizedString(for: indexed, relativeTo: Date())
            return "Last indexed \(relative) — \(indexCoordinator.status)"
        }
        return indexCoordinator.status
    }
}

#Preview {
    ContentView()
        .environmentObject(BookmarkStore())
}
    private var locationFiltersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Locations")
                    .font(.headline)
                Spacer()
                Button("All") {
                    bookmarkStore.bookmarks = bookmarkStore.bookmarks.map { b in
                        var b = b; b.isEnabled = true; return b
                    }
                    runFilteredSearch()
                }
                Button("None") {
                    bookmarkStore.bookmarks = bookmarkStore.bookmarks.map { b in
                        var b = b; b.isEnabled = false; return b
                    }
                    runFilteredSearch()
                }
            }
            ForEach(Array(bookmarkStore.bookmarks.enumerated()), id: \.offset) { index, bookmark in
                Toggle(bookmark.url.lastPathComponent, isOn: bindingForBookmark(at: index))
                    .onChange(of: bookmarkStore.bookmarks[index].isEnabled) { _ in
                        runFilteredSearch()
                    }
            }
        }
    }
