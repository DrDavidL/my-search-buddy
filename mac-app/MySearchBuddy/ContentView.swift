import SwiftUI
import AppKit
import FinderCoreFFI

struct ContentView: View {
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @EnvironmentObject private var coverageSettings: ContentCoverageSettings
    @StateObject private var indexCoordinator = IndexCoordinator()
    @StateObject private var searchViewModel = SearchViewModel()

    @FocusState private var searchFieldIsFocused: Bool
    @State private var selectedResultPath: String?
    @State private var sortBy = SortOption.score

    private let officeQuickFilterTerms = [
        "ext:doc",
        "ext:docx",
        "ext:ppt",
        "ext:pptx",
        "ext:pdf",
        "ext:xls",
        "ext:xlsx"
    ]

    var body: some View {
        HStack(spacing: 24) {
            leftPane
            Divider()
            rightPane
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 560)
        .onAppear {
            searchFieldIsFocused = true
            indexCoordinator.applySamplingPolicy(coverageSettings.samplingPolicy)
        }
        .onChange(of: searchViewModelResults) { hits in
            selectedResultPath = hits.first?.path
        }
        .onChange(of: coverageSettings.samplingPolicy) { policy in
            indexCoordinator.applySamplingPolicy(policy)
        }
        .focusedValue(\.quickLookAction, quickLookFocusedAction)
    }

    private var leftPane: some View {
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
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchControlsSection
            resultsListSection
            actionButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerSection: some View {
        Text("My Search Buddy")
            .font(.largeTitle)
            .bold()
    }

    private var locationListSection: some View {
        Group {
            if bookmarkStore.bookmarks.isEmpty {
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
                            Button {
                                bookmarkStore.remove(at: IndexSet(integer: index))
                                runFilteredSearch()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this location")
                        }
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                bookmarkStore.remove(at: IndexSet(integer: index))
                                runFilteredSearch()
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
                    .disabled(bookmarkStore.bookmarks.isEmpty)
                Button("Reset Index") { indexCoordinator.resetIndex() }
                Spacer()
            }
            Text(statusSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var locationFiltersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Locations")
                    .font(.headline)
                Spacer()
                Button("All") {
                    bookmarkStore.bookmarks = bookmarkStore.bookmarks.map { var b = $0; b.isEnabled = true; return b }
                    runFilteredSearch()
                }
                Button("None") {
                    bookmarkStore.bookmarks = bookmarkStore.bookmarks.map { var b = $0; b.isEnabled = false; return b }
                    runFilteredSearch()
                }
            }
            ForEach(Array(bookmarkStore.bookmarks.enumerated()), id: \.offset) { index, bookmark in
                Toggle(bookmark.url.lastPathComponent, isOn: bindingForBookmark(at: index))
            }
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
                quickFilterButton(title: "XLS", query: "ext:xls OR ext:xlsx")
                Button("Recent 50") { showRecentOfficeFiles() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
        }
    }

    private var searchControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Search…", text: $searchViewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFieldIsFocused)
                    .onSubmit { runFilteredSearch() }
                Button("Search") { runFilteredSearch() }
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
                runFilteredSearch()
            }

            Picker("Sort", selection: $sortBy) {
                Text("Score").tag(SortOption.score)
                Text("Modified").tag(SortOption.modified)
            }
            .pickerStyle(.segmented)
            .onChange(of: sortBy) { newValue in
                searchViewModel.sort = newValue
                runFilteredSearch()
            }

            HStack(spacing: 8) {
                Text(resultSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if searchViewModel.isSearching {
                    ProgressView().controlSize(.small)
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
                        selectedResultPath = hit.path
                        openFile(at: hit.path)
                    }
            }
        }
        .listStyle(.inset)
        .frame(minHeight: 280)
    }

    private var actionButtons: some View {
        HStack {
            Button("Open in Finder", action: revealSelectedInFinder)
                .disabled(selectedHit == nil)
            Button("Quick Look", action: quickLookSelected)
                .disabled(selectedHit == nil)
            Spacer()
        }
    }

    private var searchViewModelResults: [FinderCore.Hit] { searchViewModel.results }

    private var quickLookFocusedAction: QuickLookAction {
        QuickLookAction(isEnabled: selectedHit != nil) {
            quickLookSelected()
        }
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
                runFilteredSearch()
            } catch {
                NSLog("Failed to save bookmark: %{public}@", error.localizedDescription)
            }
        }
    }

    private func toggleIndexing() {
        if indexCoordinator.isIndexing {
            indexCoordinator.cancel()
        } else {
            indexCoordinator.startIndexing(roots: bookmarkStore.allBookmarkURLs)
        }
    }

    private func quickFilterButton(title: String, query: String) -> some View {
        Button(title) {
            searchViewModel.query = query
            runFilteredSearch()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func revealSelectedInFinder() {
        guard let hit = selectedHit else { return }
        revealInFinder(path: hit.path)
    }

    private func quickLookSelected() {
        guard let hit = selectedHit else { return }
        quickLook(path: hit.path, bookmarkStore: bookmarkStore)
    }

    private func openFile(at path: String) {
        if let scoped = bookmarkStore.scopedURL(forAbsolutePath: path) {
            NSWorkspace.shared.open(scoped.url)
            scoped.stopAccess()
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private func bindingForBookmark(at index: Int) -> Binding<Bool> {
        Binding(
            get: { bookmarkStore.bookmarks[index].isEnabled },
            set: { newValue in
                bookmarkStore.bookmarks[index].isEnabled = newValue
                runFilteredSearch()
            }
        )
    }

   private func runFilteredSearch(limit: Int? = nil) {
        let enabledPaths = bookmarkStore.bookmarks.filter { $0.isEnabled }.map { $0.url.path }
        searchViewModel.activeRootPaths = enabledPaths
        if searchViewModel.query.isEmpty {
            searchViewModel.clear()
            return
        }

        searchViewModel.runSearch(limit: limit)
    }

    private func showRecentOfficeFiles() {
        let query = officeQuickFilterTerms.joined(separator: " OR ")
        searchViewModel.query = query
        sortBy = .modified
        searchViewModel.sort = .modified
        runFilteredSearch(limit: 50)
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

fileprivate struct QuickLookAction {
    let isEnabled: Bool
    let perform: () -> Void
}

fileprivate struct QuickLookActionKey: FocusedValueKey {
    typealias Value = QuickLookAction
}

fileprivate extension FocusedValues {
    var quickLookAction: QuickLookAction? {
        get { self[QuickLookActionKey.self] }
        set { self[QuickLookActionKey.self] = newValue }
    }
}

struct QuickLookCommands: Commands {
    @FocusedValue(\.quickLookAction) private var quickLookAction

    var body: some Commands {
        CommandMenu("Preview") {
            Button("Quick Look") {
                quickLookAction?.perform()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(quickLookAction?.isEnabled != true)
        }
    }
}
