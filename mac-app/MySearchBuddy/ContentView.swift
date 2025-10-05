import SwiftUI
import AppKit
import FinderCoreFFI

struct ContentView: View {
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @EnvironmentObject private var coverageSettings: ContentCoverageSettings
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var indexCoordinator: IndexCoordinator
    @EnvironmentObject private var fileTypeFilters: FileTypeFilters
    @StateObject private var searchViewModel = SearchViewModel()

    @FocusState private var searchFieldIsFocused: Bool
    @State private var selectedResultPath: String?
    @State private var sortBy = SortOption.score
    @State private var sortOrder: SortOrder = .forward
    @State private var showFirstRunGuide = false
    @State private var showInfoModal = false
    @State private var showHelpTopic: HelpTopic?

    enum SortColumn {
        case name, size, modified, score
    }

    enum SortOrder {
        case forward, reverse
    }


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
            NSLog("[ContentView] onAppear - bookmarks: %d", bookmarkStore.bookmarks.count)
            searchFieldIsFocused = true
            indexCoordinator.applySamplingPolicy(coverageSettings.samplingPolicy)
            indexCoordinator.requestIncrementalIndexIfNeeded(roots: bookmarkStore.allBookmarkURLs)

            // Show first-run guide if this is the first time
            let firstRunCompleted = UserDefaults.standard.bool(forKey: "firstRunCompleted")
            NSLog("[ContentView] firstRunCompleted: %d", firstRunCompleted)
            if !firstRunCompleted {
                showFirstRunGuide = true
            }
        }
        .sheet(isPresented: $showFirstRunGuide) {
            FirstRunGuideView(isPresented: $showFirstRunGuide)
                .environmentObject(bookmarkStore)
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
        .sheet(isPresented: $showInfoModal) {
            InfoModalView(indexCoordinator: indexCoordinator)
        }
        .sheet(item: $showHelpTopic) { topic in
            HelpTopicView(topic: topic)
        }
        .focusedValue(\.quickLookAction, quickLookFocusedAction)
        .focusedValue(\.fileOpenAction, fileOpenFocusedAction)
        .focusedValue(\.showHelpTopic, $showHelpTopic)
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
                if searchViewModel.isSearching {
                    // Digging animation
                    Image("DogDigging")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(digAngle))
                } else if !searchViewModel.results.isEmpty {
                    // Found results - holding bone
                    Image("DogWithBone")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                } else {
                    // Idle - show digging dog without animation
                    Image("DogDigging")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
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
                HStack(spacing: 8) {
                    Text("My Search Buddy")
                        .font(.title.bold())
                        .foregroundStyle(.primary)

                    Button(action: { showInfoModal = true }) {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("About indexing and search")
                }

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
                    indexCoordinator.rebuildIndex(roots: bookmarkStore.allBookmarkURLs)
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

            // Row 1: All Office, DOC, PDF, XLS
            HStack(spacing: 6) {
                ForEach(fileTypeFilters.filters.prefix(4)) { filter in
                    Button(action: {
                        searchViewModel.query = filter.queryString
                        sortBy = .modified
                        searchViewModel.sort = .modified
                        currentSortColumn = .modified
                        sortOrder = .reverse
                        runFilteredSearch()
                    }) {
                        Label(filter.name, systemImage: filter.icon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }

            // Row 2: PPT, Code, Images
            HStack(spacing: 6) {
                ForEach(fileTypeFilters.filters.dropFirst(4).prefix(3)) { filter in
                    Button(action: {
                        searchViewModel.query = filter.queryString
                        sortBy = .modified
                        searchViewModel.sort = .modified
                        currentSortColumn = .modified
                        sortOrder = .reverse
                        runFilteredSearch()
                    }) {
                        Label(filter.name, systemImage: filter.icon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }

            // Row 3: Videos, Custom
            HStack(spacing: 6) {
                ForEach(fileTypeFilters.filters.dropFirst(7)) { filter in
                    Button(action: {
                        searchViewModel.query = filter.queryString
                        sortBy = .modified
                        searchViewModel.sort = .modified
                        currentSortColumn = .modified
                        sortOrder = .reverse
                        runFilteredSearch()
                    }) {
                        Label(filter.name, systemImage: filter.icon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
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

    private var statusSummary: String {
        let bookmarkCount = bookmarkStore.bookmarks.count
        if let indexed = indexCoordinator.lastIndexDate {
            let formatter = RelativeDateTimeFormatter()
            let relative = formatter.localizedString(for: indexed, relativeTo: Date())
            return "[\(bookmarkCount) folders] Last updated \(relative) — \(indexCoordinator.status)"
        }
        return "[\(bookmarkCount) folders] \(indexCoordinator.status)"
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

struct ShowHelpTopicKey: FocusedValueKey {
    typealias Value = Binding<HelpTopic?>
}

extension FocusedValues {
    var showHelpTopic: Binding<HelpTopic?>? {
        get { self[ShowHelpTopicKey.self] }
        set { self[ShowHelpTopicKey.self] = newValue }
    }
}

struct HelpCommands: Commands {
    @FocusedValue(\.showHelpTopic) private var showHelpTopic

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("How Indexing Works") {
                showHelpTopic?.wrappedValue = .howIndexingWorks
            }
            .disabled(showHelpTopic == nil)

            Button("Search Syntax & Tips") {
                showHelpTopic?.wrappedValue = .searchSyntax
            }
            .disabled(showHelpTopic == nil)

            Button("Quick Look Issues") {
                showHelpTopic?.wrappedValue = .quickLookIssues
            }
            .disabled(showHelpTopic == nil)

            Divider()

            Button("Adding Locations") {
                showHelpTopic?.wrappedValue = .addingLocations
            }
            .disabled(showHelpTopic == nil)

            Button("Managing Your Index") {
                showHelpTopic?.wrappedValue = .managingIndex
            }
            .disabled(showHelpTopic == nil)
        }
    }
}

struct InfoModalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var indexCoordinator: IndexCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)

                Text("About My Search Buddy")
                    .font(.title2.bold())

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Indexing Status
                    if indexCoordinator.isIndexing {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: indexCoordinator.currentPhase == .initial ? "hourglass" : "clock")
                                    .foregroundColor(.accentColor)
                                Text("Indexing in Progress")
                                    .font(.headline)
                            }

                            if indexCoordinator.currentPhase == .initial {
                                Text("**Phase 1: Quick Start** — Indexing your most recent files (last 90 days) for immediate search access. This typically takes just a few minutes.")
                                    .foregroundStyle(.secondary)
                            } else if indexCoordinator.currentPhase == .background {
                                Text("**Phase 2: Background Indexing** — Indexing older files in the background at low priority. Search is already available! This won't slow down your system.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                    }

                    // How Indexing Works
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "gearshape.2")
                                .foregroundColor(.blue)
                            Text("How Indexing Works")
                                .font(.headline)
                        }

                        Text("My Search Buddy uses a two-phase indexing approach:")
                            .font(.subheadline.bold())

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("1.")
                                    .fontWeight(.semibold)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("**Initial Phase** — Quickly indexes recent files (last 90 days) so you can start searching right away.")
                                    Text("Typical completion: 2-5 minutes")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("2.")
                                    .fontWeight(.semibold)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("**Background Phase** — Automatically continues indexing older files at low priority without impacting system performance.")
                                    Text("Runs quietly in the background")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.leading)
                    }

                    Divider()

                    // Quick Look Limitations
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "eye.trianglebadge.exclamationmark")
                                .foregroundColor(.orange)
                            Text("Quick Look Limitations")
                                .font(.headline)
                        }

                        Text("Quick Look preview may not work in these situations:")
                            .font(.subheadline)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "icloud")
                                    .foregroundColor(.orange)
                                    .frame(width: 20)
                                Text("**Cloud files** (iCloud, OneDrive) that haven't been downloaded to your Mac yet")
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "hourglass")
                                    .foregroundColor(.orange)
                                    .frame(width: 20)
                                Text("**During heavy indexing** — Quick Look may be temporarily slow or unresponsive")
                            }
                        }
                        .padding(.leading)
                    }

                    Divider()

                    // Search Tips
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass.circle")
                                .foregroundColor(.green)
                            Text("Search Tips")
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text("Use **ext:pdf** to search only PDF files")
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text("Use **quotes** for exact phrase matches: \"project report\"")
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text("Filter by location using the checkboxes on the left")
                            }
                        }
                        .padding(.leading)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Text("For more help topics, see the **Help** menu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }
}

enum HelpTopic: String, Identifiable {
    case howIndexingWorks = "How Indexing Works"
    case searchSyntax = "Search Syntax & Tips"
    case quickLookIssues = "Quick Look Issues"
    case addingLocations = "Adding Locations"
    case managingIndex = "Managing Your Index"

    var id: String { rawValue }
}

struct HelpTopicView: View {
    @Environment(\.dismiss) private var dismiss
    let topic: HelpTopic

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.blue)

                Text(topic.rawValue)
                    .font(.title2.bold())

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch topic {
                    case .howIndexingWorks:
                        howIndexingWorksContent
                    case .searchSyntax:
                        searchSyntaxContent
                    case .quickLookIssues:
                        quickLookIssuesContent
                    case .addingLocations:
                        addingLocationsContent
                    case .managingIndex:
                        managingIndexContent
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }

    private var howIndexingWorksContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("My Search Buddy uses a **two-phase indexing system** to get you searching quickly:")
                .font(.body)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Phase 1: Quick Start (Initial Indexing)**")
                    .font(.headline)

                Text("• Indexes only your most recent files (last 90 days)")
                Text("• Processes up to 20,000 files per location")
                Text("• Typically completes in 2-5 minutes")
                Text("• Runs at high priority for fast completion")
                Text("• Automatically starts when you add locations or rebuild the index")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Phase 2: Background Indexing**")
                    .font(.headline)

                Text("• Automatically starts after Phase 1 completes")
                Text("• Indexes older files (6 months, 12 months, and beyond)")
                Text("• Runs at low priority to avoid slowing your system")
                Text("• Commits changes every 30 minutes")
                Text("• You can search while this runs!")
            }
            .padding(.leading)

            Text("**Why two phases?**")
                .font(.headline)

            Text("Most users need to find recent files quickly. The two-phase approach gives you immediate access to your recent work while building complete coverage in the background.")
        }
    }

    private var searchSyntaxContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("My Search Buddy supports powerful search syntax to help you find exactly what you need.")
                .font(.body)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Basic Search**")
                    .font(.headline)

                Text("• **Simple terms**: Just type words to search file names and content")
                Text("• **Multiple words**: Searches for files containing all words")
                Text("• **Example**: `budget report` finds files with both \"budget\" and \"report\"")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Exact Phrases**")
                    .font(.headline)

                Text("• Use **quotes** for exact matches")
                Text("• **Example**: `\"quarterly report\"` finds only that exact phrase")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Filter by File Type**")
                    .font(.headline)

                Text("• Use **ext:** to search specific file types")
                Text("• **Examples**:")
                Text("  • `ext:pdf budget` — PDF files containing \"budget\"")
                Text("  • `ext:docx` — All Word documents")
                Text("  • `ext:xlsx sales` — Excel files containing \"sales\"")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Quick Filters**")
                    .font(.headline)

                Text("• Use the **Office**, **Code**, **Images**, and **Other** buttons for instant filtering")
                Text("• Filter by **location** using checkboxes on the left")
            }
            .padding(.leading)
        }
    }

    private var quickLookIssuesContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Look may not work properly in certain situations. Here's what to know:")
                .font(.body)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Cloud Files Not Downloaded**")
                    .font(.headline)

                Text("• iCloud, OneDrive, and other cloud storage services may keep files in the cloud")
                Text("• Quick Look requires files to be downloaded to your Mac")
                Text("• **Solution**: Double-click to open in the native app, which will download the file")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**During Heavy Indexing**")
                    .font(.headline)

                Text("• Quick Look may be slow or unresponsive during initial indexing (Phase 1)")
                Text("• Background indexing (Phase 2) shouldn't affect Quick Look performance")
                Text("• **Solution**: Wait a few minutes for initial indexing to complete")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**File Permissions**")
                    .font(.headline)

                Text("• Some files may require special permissions to preview")
                Text("• **Solution**: Use the keyboard shortcut **⌘O** to open the file directly")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Tips**")
                    .font(.headline)

                Text("• Use **Space bar** to toggle Quick Look")
                Text("• Use **⌘O** to open files in their default application")
                Text("• Check the info button (ⓘ) during indexing for status updates")
            }
            .padding(.leading)
        }
    }

    private var addingLocationsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("You can add any folder on your Mac to search. Here's how:")
                .font(.body)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Adding a New Location**")
                    .font(.headline)

                Text("1. Click the **Add Location...** button")
                Text("2. Navigate to the folder you want to search")
                Text("3. Click **Open** to grant access")
                Text("4. Indexing will start automatically")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Recommended Locations**")
                    .font(.headline)

                Text("• **Documents** — Your main documents folder")
                Text("• **Desktop** — Files on your desktop")
                Text("• **Downloads** — Recently downloaded files")
                Text("• **Project folders** — Specific work directories")
                Text("• **Cloud storage** — iCloud, OneDrive, Dropbox folders")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Removing Locations**")
                    .font(.headline)

                Text("• Click the **✕** button next to any location to remove it")
                Text("• Files from that location will no longer appear in search results")
                Text("• You can re-add the location later if needed")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Privacy & Security**")
                    .font(.headline)

                Text("• My Search Buddy uses secure bookmarks to access your folders")
                Text("• All indexing happens locally on your Mac")
                Text("• No data is sent to external servers")
                Text("• You can revoke access in System Settings → Privacy & Security")
            }
            .padding(.leading)
        }
    }

    private var managingIndexContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep your search index up to date and working efficiently:")
                .font(.body)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Update Index**")
                    .font(.headline)

                Text("• Scans for new and changed files in your locations")
                Text("• Uses **incremental indexing** — only processes changes")
                Text("• Runs automatically when you add new locations")
                Text("• You can also manually trigger it with the **Update Index** button")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Rebuild Index**")
                    .font(.headline)

                Text("• Completely erases and recreates the search index")
                Text("• Use this if:")
                Text("  • Search results seem incomplete or incorrect")
                Text("  • You've moved or renamed many files")
                Text("  • You want to start fresh")
                Text("• **Warning**: This will re-index all files (may take a while)")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Canceling Indexing**")
                    .font(.headline)

                Text("• Click **Cancel** while indexing to stop the process")
                Text("• Partial progress is saved")
                Text("• You can resume later with **Update Index**")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Index Storage**")
                    .font(.headline)

                Text("• The search index is stored in your Library folder")
                Text("• It's automatically managed — no manual maintenance needed")
                Text("• Size varies based on number and type of files indexed")
            }
            .padding(.leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("**Best Practices**")
                    .font(.headline)

                Text("• Let initial indexing complete for best search results")
                Text("• Use **Update Index** weekly if you add many new files")
                Text("• **Rebuild Index** only when necessary (it's time-consuming)")
            }
            .padding(.leading)
        }
    }
}

struct FirstRunGuideView: View {
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @Binding var isPresented: Bool
    @State private var includeDocuments = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image("DogDigging")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to My Search Buddy!")
                        .font(.title.bold())
                    Text("Let's get started finding your files")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)

            Divider()

            // Default folder section
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose folders to index")
                    .font(.headline)

                Text("We'll search for files in the folders you select. Most people store their important files in Documents, so we've pre-selected it for you.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $includeDocuments) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        Text(realUserDocumentsPath)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(.vertical, 8)

            Divider()

            // Cloud files info
            VStack(alignment: .leading, spacing: 12) {
                Label("About cloud files", systemImage: "info.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Filename search works")
                                .font(.body)
                            Text("We can find cloud files by name and path")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Limited until downloaded")
                                .font(.body)
                            Text("Quick Look and content search require files to be downloaded locally from iCloud/OneDrive/Dropbox")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 8)

            Divider()

            // Action buttons
            HStack {
                Button("Add More Folders Later") {
                    completeSetup()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Get Started") {
                    completeSetup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600)
    }

    private var realUserDocumentsPath: String {
        "/Users/\(NSUserName())/Documents"
    }

    private func completeSetup() {
        if includeDocuments {
            let documentsURL = URL(fileURLWithPath: realUserDocumentsPath)
            try? bookmarkStore.add(url: documentsURL)
        }

        // Mark first run as complete
        UserDefaults.standard.set(true, forKey: "firstRunCompleted")
        isPresented = false
    }
}
