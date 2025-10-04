import SwiftUI
import FinderCoreFFI

struct ResultRow: View {
    let hit: FinderCore.Hit
    @EnvironmentObject private var indexCoordinator: IndexCoordinator

    private let dateFormatter = RelativeDateTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // File icon (system or cloud)
                if isCloudPlaceholder {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.orange)
                        .help("Cloud file — download required for preview/open")
                } else {
                    Image(systemName: fileIcon)
                        .foregroundStyle(.secondary)
                }

                // File name with extension badge
                HStack(spacing: 4) {
                    Text(hit.name)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)

                    if let ext = fileExtension, !ext.isEmpty {
                        Text(ext.uppercased())
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(extensionColor)
                            .cornerRadius(3)
                    }
                }

                Spacer()

                // File size
                Text(formatSize(bytes: hit.size))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60, alignment: .trailing)

                // Modified date
                Text(formatDate(seconds: hit.mtime))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80, alignment: .trailing)
            }

            // Full path
            Text(hit.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
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

    private var isCloudPlaceholder: Bool {
        indexCoordinator.isCloudPlaceholder(path: hit.path)
    }

    private var fileExtension: String? {
        let components = hit.name.components(separatedBy: ".")
        return components.count > 1 ? components.last : nil
    }

    private var fileIcon: String {
        guard let ext = fileExtension?.lowercased() else { return "doc" }

        switch ext {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        case "ppt", "pptx": return "rectangle.on.rectangle.angled"
        case "txt", "md": return "doc.plaintext"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        case "mp4", "mov", "avi": return "video"
        case "mp3", "wav", "aiff": return "music.note"
        case "zip", "tar", "gz": return "doc.zipper"
        case "swift", "rs", "py", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    private var extensionColor: Color {
        guard let ext = fileExtension?.lowercased() else { return .gray }

        switch ext {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx": return .green
        case "ppt", "pptx": return .orange
        case "txt", "md": return .gray
        case "jpg", "jpeg", "png", "gif", "heic": return .purple
        case "mp4", "mov", "avi": return .pink
        case "mp3", "wav", "aiff": return .cyan
        case "zip", "tar", "gz": return .brown
        case "swift", "rs", "py", "js", "ts": return .indigo
        default: return .gray
        }
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
    .environmentObject(IndexCoordinator())
    .padding()
}
