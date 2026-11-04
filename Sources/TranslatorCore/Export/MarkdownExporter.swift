import Foundation

public enum MarkdownExporter {
    public static func render(segments: [Segment], pauses: [PauseMarker] = [], sessionStart: Date) -> String {
        var lines = ["# 실적 발표 번역 — \(format(sessionStart, "yyyy-MM-dd HH:mm"))", ""]
        for entry in TranscriptEntry.interleave(segments: segments, pauses: pauses) {
            switch entry {
            case .segment(let segment):
                lines.append("**[\(timestamp(segment.start))]** \(segment.english)")
                lines.append("> \(translationLine(segment))")
            case .pause(let marker):
                lines.append("---")
                lines.append("_\(marker.label)_")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func fileName(for sessionStart: Date) -> String {
        format(sessionStart, "yyyy-MM-dd_HHmm") + ".md"
    }

    private static func translationLine(_ segment: Segment) -> String {
        switch segment.status {
        case .pending, .translating:
            return "(번역 대기 중)"
        case .done:
            return segment.korean ?? "(번역 대기 중)"
        case .flagged:
            return "⚠ " + (segment.korean ?? "(번역 없음)")
        }
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
