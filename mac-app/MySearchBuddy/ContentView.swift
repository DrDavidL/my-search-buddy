import SwiftUI
import AppKit
import FinderCoreFFI

struct ContentView: View {
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @EnvironmentObject private var coverageSettings: ContentCoverageSettings
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var indexCoordinator: IndexCoordinator
    @StateObject private var searchViewModel = SearchViewModel()

    @FocusState private var searchFieldIsFocused: Bool
    @State private var selectedResultPath: String?
    @State private var sortBy = SortOption.score
    @State private var sortOrder: SortOrder = .forward

    enum SortColumn {
        case name, size, modified, score
    }

    enum SortOrder {
        case forward, reverse
    }

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
        ZStack {
            mainContent
                .blur(radius: shouldShowPaywall ? 4 : 0)
                .disabled(shouldShowPaywall)

            if !purchaseManager.isReady {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView("Preparing purchases…")
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .shadow(radius: 12)
            } else if shouldShowPaywall {
                Color.black.opacity(0.35).ignoresSafeArea()
                SubscriptionPaywallView()
                    .environmentObject(purchaseManager)
            }
        }
        .task {
            await purchaseManager.start()
        }
    }

    private var shouldShowPaywall: Bool {
        purchaseManager.isReady && !purchaseManager.subscriptionActive
    }

    private var mainContent: some View {
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
            indexCoordinator.requestIncrementalIndexIfNeeded(roots: bookmarkStore.allBookmarkURLs)
        }
        .onChange(of: searchViewModelResults) { hits in
            selectedResultPath = hits.first?.path
        }
        .onChange(of: coverageSettings.samplingPolicy) { policy in
            indexCoordinator.applySamplingPolicy(policy)
        }
        .onChange(of: bookmarkStore.bookmarks) { _ in
            indexCoordinator.requestIncrementalIndexIfNeeded(roots: bookmarkStore.allBookmarkURLs)
        }
        .focusedValue(\.quickLookAction, quickLookFocusedAction)
        .focusedValue(\.fileOpenAction, fileOpenFocusedAction)
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
        HStack(spacing: 12) {
            // Search dog mascot
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 50, height: 50)

                if searchViewModel.isSearching {
                    // Digging animation
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                        .rotationEffect(.degrees(digAngle))
                } else if !searchViewModel.results.isEmpty {
                    // Found results - holding bone
                    Image(systemName: "rectangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.brown)
                        .rotationEffect(.degrees(-45))
                        .overlay(
                            Circle()
                                .fill(.brown)
                                .frame(width: 6, height: 6)
                                .offset(x: -8, y: -8)
                        )
                        .overlay(
                            Circle()
                                .fill(.brown)
                                .frame(width: 6, height: 6)
                                .offset(x: 8, y: 8)
                        )
                } else {
                    // Idle - cute dog face
                    Image(systemName: "pawprint.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                }
            }
            .onAppear {
                if searchViewModel.isSearching {
                    startDigAnimation()
                }
            }
            .onChange(of: searchViewModel.isSearching) { isSearching in
                if isSearching {
                    startDigAnimation()
                } else {
                    digTimer?.invalidate()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("My Search Buddy")
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                Text(dogStatusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.3), value: dogStatusMessage)
            }

            Spacer()
        }
    }

    @State private var digAngle: Double = 0
    @State private var digTimer: Timer?

    private func startDigAnimation() {
        digTimer?.invalidate()
        digTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                digAngle = digAngle == 0 ? 25 : (digAngle == 25 ? -25 : 0)
            }
        }
    }

    private var dogStatusMessage: String {
        if searchViewModel.isSearching {
            return "Digging for files..."
        } else if !searchViewModel.results.isEmpty {
            return "Found \(searchViewModel.results.count) file\(searchViewModel.results.count == 1 ? "" : "s")!"
        } else if !searchViewModel.query.isEmpty {
            return "No matches found"
        } else {
            return "Ready to search"
        }
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
                Button(indexCoordinator.isIndexing ? "Cancel" : "Update Index", action: toggleIndexing)
                    .disabled(bookmarkStore.bookmarks.isEmpty)
                    .help("Scan bookmarked folders for new or changed files")
                Button("Rebuild Index") {
                    indexCoordinator.resetIndex()
                    indexCoordinator.startIndexing(roots: bookmarkStore.allBookmarkURLs, mode: .full)
                }
                    .help("Erase and recreate the entire search index")
                    .disabled(bookmarkStore.bookmarks.isEmpty)
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
                if !searchViewModel.query.isEmpty {
                    Text("↩ Open • ␣ Quick Look • ⌘R Reveal in Finder")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var resultsListSection: some View {
        VStack(spacing: 0) {
            // Column headers
            if !searchViewModelResults.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "doc")
                        .frame(width: 20)
                        .opacity(0) // Spacer for icon column

                    sortableHeader(title: "Name", column: .name)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    sortableHeader(title: "Size", column: .size)
                        .frame(width: 70, alignment: .trailing)

                    sortableHeader(title: "Modified", column: .modified)
                        .frame(width: 90, alignment: .trailing)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(alignment: .bottom) {
                    Divider()
                }
            }

            List(selection: $selectedResultPath) {
                ForEach(sortedResults, id: \.path) { hit in
                    ResultRow(hit: hit)
                        .environmentObject(indexCoordinator)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            selectedResultPath = hit.path
                            openFile(at: hit.path)
                        }
                        .onTapGesture {
                            selectedResultPath = hit.path
                        }
                }
            }
            .listStyle(.inset)
        }
        .frame(minHeight: 280)
    }

    private func sortableHeader(title: String, column: SortColumn) -> some View {
        Button(action: {
            if currentSortColumn == column {
                sortOrder = sortOrder == .forward ? .reverse : .forward
            } else {
                currentSortColumn = column
                sortOrder = .forward
            }
        }) {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                if currentSortColumn == column {
                    Image(systemName: sortOrder == .forward ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(currentSortColumn == column ? .primary : .secondary)
    }

    @State private var currentSortColumn: SortColumn = .score

    private var sortedResults: [FinderCore.Hit] {
        let results = searchViewModelResults
        let sorted = results.sorted { lhs, rhs in
            let comparison: Bool
            switch currentSortColumn {
            case .name:
                comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .size:
                comparison = lhs.size < rhs.size
            case .modified:
                comparison = lhs.mtime < rhs.mtime
            case .score:
                comparison = lhs.score > rhs.score // Higher score first
            }
            return sortOrder == .forward ? comparison : !comparison
        }
        return sorted
    }

    private var actionButtons: some View {
        HStack {
            Button("Open in Finder", action: revealSelectedInFinder)
                .disabled(selectedHit == nil)
                .keyboardShortcut("r", modifiers: .command)
            Button("Quick Look", action: quickLookSelected)
                .disabled(selectedHit == nil)
                .keyboardShortcut(.space, modifiers: [])
            Button("Open", action: openSelectedFile)
                .disabled(selectedHit == nil)
                .keyboardShortcut(.return, modifiers: .command)
            Spacer()
        }
    }

    private func openSelectedFile() {
        guard let hit = selectedHit else { return }
        openFile(at: hit.path)
    }

    private var searchViewModelResults: [FinderCore.Hit] { searchViewModel.results }

    private var quickLookFocusedAction: QuickLookAction {
        QuickLookAction(isEnabled: selectedHit != nil) {
            quickLookSelected()
        }
    }

    private var fileOpenFocusedAction: FileOpenAction {
        FileOpenAction { openSelectedFile() }
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
            indexCoordinator.startIndexing(roots: bookmarkStore.allBookmarkURLs, mode: .incremental)
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
        if indexCoordinator.isCloudPlaceholder(path: hit.path) {
            showCloudPlaceholderAlert(for: hit.path)
            return
        }
        quickLook(path: hit.path, bookmarkStore: bookmarkStore)
    }

    private func openFile(at path: String) {
        if indexCoordinator.isCloudPlaceholder(path: path) {
            showCloudPlaceholderAlert(for: path)
            return
        }
        if let scoped = bookmarkStore.scopedURL(forAbsolutePath: path) {
            NSWorkspace.shared.open(scoped.url)
            scoped.stopAccess()
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private func showCloudPlaceholderAlert(for path: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        alert.messageText = "Download Required"
        alert.informativeText = "\(fileName) is stored in the cloud. Download it locally before previewing or opening."
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
            return "Last updated \(relative) — \(indexCoordinator.status)"
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

struct FileOpenAction {
    let perform: () -> Void
}

struct FileOpenActionKey: FocusedValueKey {
    typealias Value = FileOpenAction
}

extension FocusedValues {
    var fileOpenAction: FileOpenAction? {
        get { self[FileOpenActionKey.self] }
        set { self[FileOpenActionKey.self] = newValue }
    }
}

struct FileCommands: Commands {
    @FocusedValue(\.fileOpenAction) private var fileOpenAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open") {
                fileOpenAction?.perform()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(fileOpenAction == nil)
        }
    }
}
