import SwiftUI
import FinderCoreFFI

struct ResultRow: View {
    let hit: FinderCore.Hit

    private let dateFormatter = RelativeDateTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hit.name)
                .font(.headline)
            HStack(spacing: 8) {
                Text(hit.path)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatSize(bytes: hit.size))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(formatDate(seconds: hit.mtime))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(seconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        return dateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatSize(bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    ResultRow(
        hit: FinderCore.Hit(
            path: "/Users/david/Documents/report.txt",
            name: "report.txt",
            mtime: Int64(Date().addingTimeInterval(-3600).timeIntervalSince1970),
            size: 42_000,
            score: 3.14
        )
    )
    .padding()
}
