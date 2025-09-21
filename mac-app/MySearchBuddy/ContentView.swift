import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bookmarkStore: BookmarkStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("My Search Buddy")
                .font(.largeTitle)
                .bold()

            if bookmarkStore.urls.isEmpty {
                Text("Add a folder to begin indexing.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(Array(bookmarkStore.urls.enumerated()), id: \.offset) { _, url in
                        Text(url.path)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .textSelection(.enabled)
                    }
                    .onDelete(perform: bookmarkStore.remove)
                }
                .frame(minHeight: 200)
            }

            HStack {
                Button("Add Location…", action: showPicker)
                Spacer()
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
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
}

#Preview {
    ContentView()
        .environmentObject(BookmarkStore())
}
