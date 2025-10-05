import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coverageSettings: ContentCoverageSettings
    @EnvironmentObject private var indexCoordinator: IndexCoordinator
    @EnvironmentObject private var fileTypeFilters: FileTypeFilters

    var body: some View {
        TabView {
            indexingSettingsTab
                .tabItem {
                    Label("Indexing", systemImage: "gearshape")
                }

            fileTypeFiltersTab
                .tabItem {
                    Label("Quick Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
        }
        .frame(width: 600, height: 500)
    }

    private var indexingSettingsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Indexing")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Content coverage: \(labelText)")
                    .font(.subheadline)

                Slider(
                    value: coverageSettings.bindingForSlider(),
                    in: coverageSettings.sliderRange,
                    step: 1
                )
                .disabled(coverageSettings.isOverrideActive)

                Text(
                    "Indexes the first \(headText) and the final \(tailText) of each file (\(labelText) total)."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                if coverageSettings.isOverrideActive {
                    Text("Currently overridden by the MSB_CONTENT_PERCENT environment variable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Schedule automatic updates between 2–4 AM", isOn: $indexCoordinator.scheduleWindowEnabled)
                    .toggleStyle(.switch)

                if let nextRun = indexCoordinator.nextScheduledRun {
                    Text("Next scheduled run: \(scheduleFormatter.string(from: nextRun))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { coverageSettings.refreshPolicy() }
    }

    private var fileTypeFiltersTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Customize Quick Filters")
                .font(.headline)

            Text("Configure file extensions for each quick filter button. Separate extensions with commas (without dots).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(fileTypeFilters.filters.enumerated()), id: \.element.id) { index, filter in
                        FileTypeFilterEditor(
                            filter: filter,
                            onUpdate: { newExtensions in
                                fileTypeFilters.updateFilter(id: filter.id, extensions: newExtensions)
                            }
                        )
                    }
                }
            }

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    fileTypeFilters.resetToDefaults()
                }

                Spacer()
            }
        }
        .padding(20)
    }

    private var labelText: String {
        String(format: "%.0f%%", coverageSettings.effectivePercentage)
    }

    private var headText: String {
        String(format: "%.1f%%", coverageSettings.headPercentage)
    }

    private var tailText: String {
        String(format: "%.1f%%", coverageSettings.tailPercentage)
    }

    private var scheduleFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

struct FileTypeFilterEditor: View {
    let filter: FileTypeFilter
    let onUpdate: ([String]) -> Void

    @State private var extensionsText: String

    init(filter: FileTypeFilter, onUpdate: @escaping ([String]) -> Void) {
        self.filter = filter
        self.onUpdate = onUpdate
        _extensionsText = State(initialValue: filter.extensions.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: filter.icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 20)

                Text(filter.name)
                    .font(.subheadline.bold())
            }

            TextField("Extensions (e.g., pdf, docx, txt)", text: $extensionsText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: extensionsText) { newValue in
                    let extensions = newValue
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    onUpdate(extensions)
                }

            Text("Current: \(filter.extensions.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ContentCoverageSettings())
        .environmentObject(IndexCoordinator())
        .environmentObject(FileTypeFilters())
}
