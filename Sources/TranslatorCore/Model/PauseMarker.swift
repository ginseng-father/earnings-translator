import Foundation

/// Where the user pressed 정지 in a transcript that later continued.
public struct PauseMarker: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let pausedAt: Date
    public var resumedAt: Date?
    /// Number of segments before the pause; the marker is shown after them.
    public let afterSegment: Int

    public init(id: UUID = UUID(), pausedAt: Date, resumedAt: Date? = nil, afterSegment: Int) {
        self.id = id
        self.pausedAt = pausedAt
        self.resumedAt = resumedAt
        self.afterSegment = afterSegment
    }

    public var label: String {
        var text = "⏸ \(Self.time(pausedAt)) 정지"
        if let resumedAt {
            text += " · \(Self.time(resumedAt)) 다시 시작 (\(Self.duration(resumedAt.timeIntervalSince(pausedAt))))"
        }
        return text
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        if minutes > 0 { return "\(minutes)분 \(secs)초" }
        return "\(secs)초"
    }
}

/// One row of the transcript: a sentence or a pause marker.
public enum TranscriptEntry: Sendable, Equatable, Identifiable {
    case segment(Segment)
    case pause(PauseMarker)

    public var id: UUID {
        switch self {
        case .segment(let segment): return segment.id
        case .pause(let marker): return marker.id
        }
    }

    public static func interleave(segments: [Segment], pauses: [PauseMarker]) -> [TranscriptEntry] {
        var entries: [TranscriptEntry] = []
        var remaining = pauses.sorted { $0.afterSegment < $1.afterSegment }[...]
        for (index, segment) in segments.enumerated() {
            while let next = remaining.first, next.afterSegment <= index {
                entries.append(.pause(next))
                remaining = remaining.dropFirst()
            }
            entries.append(.segment(segment))
        }
        entries += remaining.map(TranscriptEntry.pause)
        return entries
    }
}
