import Foundation

public enum SegmentStatus: Sendable, Equatable {
    case pending, translating, done
    case flagged([ValidationIssue])
}

/// One transcribed English sentence and its translation.
public struct Segment: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// Seconds since the session started.
    public let start: TimeInterval
    public let english: String
    public var korean: String?
    public var status: SegmentStatus

    public init(id: UUID = UUID(), start: TimeInterval, english: String, korean: String? = nil, status: SegmentStatus = .pending) {
        self.id = id
        self.start = start
        self.english = english
        self.korean = korean
        self.status = status
    }
}
