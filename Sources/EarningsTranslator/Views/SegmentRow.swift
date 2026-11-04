import SwiftUI
import TranslatorCore

struct SegmentRow: View {
    static let flagHelp = "번역의 숫자나 용어가 영어 원문과 다를 수 있습니다. 영어 받아쓰기 자체의 오류는 검사하지 않습니다."

    let segment: Segment
    let sessionActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(segment.english)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if case .flagged = segment.status {
                    Text("⚠")
                        .font(.title3)
                        .help(Self.flagHelp)
                }
                let shown = SegmentPresentation.koreanText(segment, sessionActive: sessionActive)
                Text(shown.text)
                    .font(.title3)
                    .foregroundStyle(shown.isPlaceholder ? .tertiary : .primary)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

struct LiveRow: View {
    let english: String

    var body: some View {
        Text(english)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Where 정지 was pressed; the transcript continues below it.
struct PauseRow: View {
    let marker: PauseMarker

    var body: some View {
        HStack(spacing: 8) {
            line
            Text(marker.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            line
        }
        .padding(.vertical, 10)
    }

    private var line: some View {
        Rectangle().fill(.separator).frame(height: 1)
    }
}
