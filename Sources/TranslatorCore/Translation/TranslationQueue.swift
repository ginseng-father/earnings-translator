import Foundation

public struct SegmentUpdate: Sendable, Equatable {
    public let id: UUID
    public let korean: String?
    public let status: SegmentStatus

    public init(id: UUID, korean: String?, status: SegmentStatus) {
        self.id = id
        self.korean = korean
        self.status = status
    }
}

public enum QueueHealth: Sendable, Equatable {
    case ok
    case delayed(backlog: Int)
    case offline
}

/// Translates segments in order, one request at a time. When sentences pile
/// up they go out together in one batch; nothing is ever dropped. Each result
/// is validated, and a failing one is retried once on its own with hints.
public actor TranslationQueue {
    private let backend: any TranslationBackend
    private let glossary: Glossary
    private let maxBatch: Int
    private let delayedThreshold: Int
    private let contextSize: Int
    private let retryInterval: Duration

    private var pending: [Segment] = []
    private var context: [ContextPair] = []
    private var isWorking = false
    private var isOffline = false
    private var lastHealth: QueueHealth = .ok
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public nonisolated let updates: AsyncStream<SegmentUpdate>
    public nonisolated let health: AsyncStream<QueueHealth>
    private let updateSink: AsyncStream<SegmentUpdate>.Continuation
    private let healthSink: AsyncStream<QueueHealth>.Continuation

    public init(
        backend: any TranslationBackend,
        glossary: Glossary,
        maxBatch: Int = 6,
        delayedThreshold: Int = 4,
        contextSize: Int = 3,
        retryInterval: Duration = .seconds(3)
    ) {
        self.backend = backend
        self.glossary = glossary
        self.maxBatch = maxBatch
        self.delayedThreshold = delayedThreshold
        self.contextSize = contextSize
        self.retryInterval = retryInterval
        (updates, updateSink) = AsyncStream.makeStream(of: SegmentUpdate.self)
        (health, healthSink) = AsyncStream.makeStream(of: QueueHealth.self, bufferingPolicy: .bufferingNewest(32))
    }

    public func enqueue(_ segment: Segment) {
        pending.append(segment)
        reportBacklog()
        guard !isWorking else { return }
        isWorking = true
        Task { await self.drain() }
    }

    /// Returns once everything queued so far is translated, or the backend is offline.
    public func finish() async {
        guard isWorking, !isOffline else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func drain() async {
        while !pending.isEmpty {
            let batch = Array(pending.prefix(maxBatch))
            for segment in batch {
                updateSink.yield(SegmentUpdate(id: segment.id, korean: nil, status: .translating))
            }
            let results = await translate(batch)
            pending.removeFirst(batch.count)
            for (segment, update) in zip(batch, results) {
                updateSink.yield(update)
                if update.status == .done, let korean = update.korean {
                    context.append(ContextPair(english: segment.english, korean: korean))
                    context = Array(context.suffix(contextSize))
                }
            }
            reportBacklog()
        }
        isWorking = false
        resumeIdleWaiters()
    }

    private func translate(_ batch: [Segment]) async -> [SegmentUpdate] {
        let items = batch.enumerated().map { TranslationItem(id: $0.offset + 1, english: $0.element.english) }
        let replies = await request(items, hints: [])
        var results: [SegmentUpdate] = []
        for (item, segment) in zip(items, batch) {
            let first = replies?[item.id]
            // A missing reply (dropped id, malformed batch) gets a fresh single try,
            // same as a reply that fails validation.
            let issues = first.map { validate(segment, $0) } ?? [.emptyTranslation]
            if issues.isEmpty, let first {
                results.append(SegmentUpdate(id: segment.id, korean: first, status: .done))
                continue
            }
            let retryHints = first == nil ? [] : issues
            let retry = await request([TranslationItem(id: 1, english: segment.english)], hints: retryHints)?[1]
            let retryIssues = retry.map { validate(segment, $0) } ?? [.emptyTranslation]
            let korean = retry ?? first
            let status: SegmentStatus = retryIssues.isEmpty ? .done : .flagged(retryIssues)
            results.append(SegmentUpdate(id: segment.id, korean: korean, status: status))
        }
        return results
    }

    /// Waits out an unreachable backend; any other failure yields `nil`.
    private func request(_ items: [TranslationItem], hints: [ValidationIssue]) async -> [Int: String]? {
        while true {
            do {
                let replies = try await backend.translate(items, context: context, hints: hints)
                if isOffline {
                    isOffline = false
                    reportBacklog()
                }
                return replies
            } catch BackendError.unreachable {
                if !isOffline {
                    isOffline = true
                    setHealth(.offline)
                    resumeIdleWaiters()
                }
                try? await Task.sleep(for: retryInterval)
            } catch {
                return nil
            }
        }
    }

    private func validate(_ segment: Segment, _ korean: String) -> [ValidationIssue] {
        TranslationValidator.validate(english: segment.english, korean: korean, glossary: glossary)
    }

    private func reportBacklog() {
        guard !isOffline else { return }
        setHealth(pending.count >= delayedThreshold ? .delayed(backlog: pending.count) : .ok)
    }

    private func setHealth(_ health: QueueHealth) {
        guard health != lastHealth else { return }
        lastHealth = health
        healthSink.yield(health)
    }

    private func resumeIdleWaiters() {
        idleWaiters.forEach { $0.resume() }
        idleWaiters = []
    }
}
