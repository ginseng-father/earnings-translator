import AppKit
import SwiftUI

/// "저장됨 22:46:28 · 폴더/파일.md"; clicking shows the file in Finder.
struct SaveNoticeView: View {
    let notice: SaveNotice

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([notice.url])
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("저장됨 \(time)")
                Text(location)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .help("\(notice.url.path)\n클릭하면 Finder에서 보여 줍니다.")
    }

    /// 24-hour, like the pause markers.
    private var time: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: notice.date)
    }

    /// Home shortened to ~, e.g. ~/Documents/2026-11-04_183015-123.md
    private var location: String {
        let path = notice.url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
