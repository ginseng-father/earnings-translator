import Foundation

/// Serializes start/stop so a second press while a session is starting or
/// stopping is ignored instead of tearing down the other half-built session.
public struct SessionGate: Sendable {
    public enum Phase: Sendable, Equatable { case idle, starting, running, stopping }

    public private(set) var phase: Phase = .idle

    public init() {}

    public mutating func beginStart() -> Bool {
        guard phase == .idle else { return false }
        phase = .starting
        return true
    }

    public mutating func finishStart(running: Bool) {
        phase = running ? .running : .idle
    }

    public mutating func beginStop() -> Bool {
        guard phase == .running else { return false }
        phase = .stopping
        return true
    }

    public mutating func finishStop() {
        phase = .idle
    }
}

/// Reports when nothing has arrived for `timeout` seconds — used to notice a
/// capture that stopped delivering audio buffers mid-session.
public struct StallDetector: Sendable {
    public let timeout: TimeInterval
    private var last: Date

    public init(timeout: TimeInterval, startedAt: Date = Date()) {
        self.timeout = timeout
        last = startedAt
    }

    public mutating func feed(at date: Date = Date()) {
        last = date
    }

    public func isStalled(now: Date = Date()) -> Bool {
        now.timeIntervalSince(last) > timeout
    }
}
