import Foundation

/// Keeps the session's Markdown file up to date: writes atomically every
/// `interval` while there are unsaved changes, and on `flush()`. A failed
/// write keeps the changes pending so a later attempt (or a new folder) saves them.
public actor TranscriptAutosaver {
    private var folder: URL
    private let sessionStart: Date
    private let interval: Duration
    private var segments: [Segment] = []
    private var pauses: [PauseMarker] = []
    private var dirty = false
    private var timer: Task<Void, Never>?

    public nonisolated let errors: AsyncStream<any Error>
    private let errorSink: AsyncStream<any Error>.Continuation

    public init(folder: URL, sessionStart: Date, interval: Duration = .seconds(5)) {
        self.folder = folder
        self.sessionStart = sessionStart
        self.interval = interval
        (errors, errorSink) = AsyncStream.makeStream(of: (any Error).self, bufferingPolicy: .bufferingNewest(8))
    }

    deinit {
        timer?.cancel()
    }

    public var fileURL: URL {
        folder.appendingPathComponent(MarkdownExporter.fileName(for: sessionStart))
    }

    public func update(_ segments: [Segment], pauses: [PauseMarker] = []) {
        self.segments = segments
        self.pauses = pauses
        dirty = true
        if timer == nil {
            timer = Task { [interval] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    await self.flushReportingErrors()
                }
            }
        }
    }

    public func setFolder(_ url: URL) {
        folder = url
        dirty = !segments.isEmpty
    }

    public func flush() throws {
        guard dirty else { return }
        try MarkdownExporter.write(segments: segments, pauses: pauses, sessionStart: sessionStart, to: folder)
        dirty = false
    }

    /// Stops the timer after a final save.
    public func close() throws {
        timer?.cancel()
        timer = nil
        try flush()
    }

    private func flushReportingErrors() {
        do {
            try flush()
        } catch {
            errorSink.yield(error)
        }
    }
}
