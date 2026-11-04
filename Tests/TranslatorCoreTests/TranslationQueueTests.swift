import Foundation
import Testing
@testable import TranslatorCore

/// Scripted backend: `respond` sees each call's items, hints and call number.
actor FakeBackend: TranslationBackend {
    typealias Responder = @Sendable (_ items: [TranslationItem], _ hints: [ValidationIssue], _ call: Int) async throws -> [Int: String]
    struct Call { let items: [TranslationItem]; let hints: [ValidationIssue]; let context: [ContextPair] }

    private(set) var calls: [Call] = []
    private let respond: Responder

    init(_ respond: @escaping Responder) { self.respond = respond }

    func translate(_ items: [TranslationItem], context: [ContextPair], hints: [ValidationIssue]) async throws -> [Int: String] {
        calls.append(Call(items: items, hints: hints, context: context))
        return try await respond(items, hints, calls.count)
    }

    func health() async -> BackendHealth { .ok }
}

actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// Echoes a Korean rendering that passes validation for simple sentences.
let echo: FakeBackend.Responder = { items, _, _ in
    Dictionary(uniqueKeysWithValues: items.map { ($0.id, "번역: " + $0.english.filter(\.isNumber)) })
}

func makeQueue(_ backend: FakeBackend) -> TranslationQueue {
    TranslationQueue(backend: backend, glossary: Glossary(entries: []), retryInterval: .milliseconds(10))
}

/// Collects updates until `count` segments reach a terminal status.
func terminalUpdates(_ queue: TranslationQueue, count: Int) async throws -> [SegmentUpdate] {
    try await withThrowingTaskGroup(of: [SegmentUpdate].self) { group in
        group.addTask {
            var all: [SegmentUpdate] = []
            var finished = 0
            for await update in queue.updates {
                all.append(update)
                if case .translating = update.status { continue }
                if case .pending = update.status { continue }
                finished += 1
                if finished == count { break }
            }
            return all
        }
        group.addTask {
            try await Task.sleep(for: .seconds(5))
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

func segment(_ english: String) -> Segment { Segment(start: 0, english: english) }

struct TranslationQueueTests {
    @Test func singleSegmentIsTranslated() async throws {
        let queue = makeQueue(FakeBackend(echo))
        let s = segment("Hello 5")
        await queue.enqueue(s)
        let updates = try await terminalUpdates(queue, count: 1)
        #expect(updates.map(\.status) == [.translating, .done])
        #expect(updates.last?.korean == "번역: 5")
        #expect(updates.allSatisfy { $0.id == s.id })
    }

    @Test func backlogIsBatched() async throws {
        let gate = Gate()
        let backend = FakeBackend { items, hints, call in
            if call == 1 { await gate.wait() }
            return try await echo(items, hints, call)
        }
        let queue = makeQueue(backend)
        let segments = (1...5).map { segment("line \($0)") }
        for s in segments { await queue.enqueue(s) }
        await gate.open()
        _ = try await terminalUpdates(queue, count: 5)
        let calls = await backend.calls
        #expect(calls.count == 2)
        #expect(calls[0].items.map(\.english) == ["line 1"])
        #expect(calls[1].items.map(\.english) == ["line 2", "line 3", "line 4", "line 5"])
    }

    @Test func failedValidationRetriesOnceWithHints() async throws {
        let backend = FakeBackend { items, _, call in
            [items[0].id: call == 1 ? "매출 94억 달러" : "매출 949억 달러"]
        }
        let queue = makeQueue(backend)
        await queue.enqueue(segment("Revenue was $94.9 billion."))
        let updates = try await terminalUpdates(queue, count: 1)
        #expect(updates.last?.status == .done)
        #expect(updates.last?.korean == "매출 949억 달러")
        let calls = await backend.calls
        #expect(calls.count == 2)
        #expect(calls[1].items.count == 1)
        #expect(calls[1].hints.contains(.missingQuantity(q("94900000000"))))
    }

    @Test func secondFailureIsFlagged() async throws {
        let backend = FakeBackend { items, _, _ in [items[0].id: "매출 94억 달러"] }
        let queue = makeQueue(backend)
        await queue.enqueue(segment("Revenue was $94.9 billion."))
        let updates = try await terminalUpdates(queue, count: 1)
        guard case .flagged(let issues) = updates.last?.status else { Issue.record("expected flagged"); return }
        #expect(issues.contains(.missingQuantity(q("94900000000"))))
        #expect(updates.last?.korean == "매출 94억 달러")
        #expect(await backend.calls.count == 2)
    }

    @Test func emptyTranslationIsFlagged() async throws {
        let queue = makeQueue(FakeBackend { items, _, _ in [items[0].id: "  "] })
        await queue.enqueue(segment("Thank you."))
        let updates = try await terminalUpdates(queue, count: 1)
        #expect(updates.last?.status == .flagged([.emptyTranslation]))
    }

    @Test func batchReplyWithWrongCountFallsBackToSingles() async throws {
        let gate = Gate()
        let backend = FakeBackend { items, hints, call in
            if call == 1 { await gate.wait(); return try await echo(items, hints, call) }
            if items.count > 1 { return [items[0].id: "번역: 2"] } // drops the rest
            return try await echo(items, hints, call)
        }
        let queue = makeQueue(backend)
        let segments = ["a 1", "b 2", "c 3", "d 4"].map(segment)
        for s in segments { await queue.enqueue(s) }
        await gate.open()
        let updates = try await terminalUpdates(queue, count: 4)
        let final = Dictionary(updates.filter { $0.status == .done }.map { ($0.id, $0.korean) }, uniquingKeysWith: { $1 })
        #expect(final.count == 4)
        #expect(final[segments[3].id] == "번역: 4")
    }

    @Test func malformedBatchFallsBackToSingles() async throws {
        let gate = Gate()
        let backend = FakeBackend { items, hints, call in
            if call == 1 { await gate.wait(); return try await echo(items, hints, call) }
            if items.count > 1 { throw BackendError.malformedResponse }
            return try await echo(items, hints, call)
        }
        let queue = makeQueue(backend)
        for s in ["a 1", "b 2", "c 3"].map(segment) { await queue.enqueue(s) }
        await gate.open()
        let updates = try await terminalUpdates(queue, count: 3)
        #expect(updates.filter { $0.status == .done }.count == 3)
    }

    @Test func offlineKeepsOrderAndResumes() async throws {
        let backend = FakeBackend { items, hints, call in
            if call <= 2 { throw BackendError.unreachable }
            return try await echo(items, hints, call)
        }
        let queue = makeQueue(backend)
        let healthTask = Task {
            var seen: [QueueHealth] = []
            for await h in queue.health {
                seen.append(h)
                if seen.contains(.offline), h == .ok { break }
            }
            return seen
        }
        let segments = ["a 1", "b 2"].map(segment)
        for s in segments { await queue.enqueue(s) }
        let updates = try await terminalUpdates(queue, count: 2)
        #expect(updates.filter { $0.status == .done }.map(\.id) == segments.map(\.id))
        let health = await healthTask.value
        #expect(health.contains(.offline))
        #expect(health.last == .ok)
    }

    @Test func delayedHealthReported() async throws {
        let gate = Gate()
        let backend = FakeBackend { items, hints, call in
            await gate.wait()
            return try await echo(items, hints, call)
        }
        let queue = makeQueue(backend)
        let healthTask = Task {
            for await h in queue.health { if case .delayed = h { return h } }
            return QueueHealth.ok
        }
        for i in 1...5 { await queue.enqueue(segment("line \(i)")) }
        let health = await healthTask.value
        guard case .delayed(let backlog) = health else { Issue.record("expected delayed"); return }
        #expect(backlog >= 4)
        await gate.open()
        _ = try await terminalUpdates(queue, count: 5)
    }

    @Test func contextUsesLastThreeDonePairs() async throws {
        let backend = FakeBackend(echo)
        let queue = makeQueue(backend)
        for i in 1...5 {
            await queue.enqueue(segment("line \(i)"))
            await queue.finish()
        }
        let last = await backend.calls.last!
        #expect(last.context.map(\.english) == ["line 2", "line 3", "line 4"])
    }

    @Test func queueIdlesAndResumes() async throws {
        let backend = FakeBackend(echo)
        let queue = makeQueue(backend)
        await queue.enqueue(segment("first 1"))
        await queue.finish()
        try await Task.sleep(for: .milliseconds(50))
        await queue.enqueue(segment("later 2"))
        await queue.finish()
        #expect(await backend.calls.count == 2)
    }

    @Test func cancelStopsOfflineRetries() async throws {
        let backend = FakeBackend { _, _, _ in throw BackendError.unreachable }
        let queue = makeQueue(backend)
        await queue.enqueue(segment("a 1"))
        try await Task.sleep(for: .milliseconds(50))
        await queue.cancel()
        let callsAtCancel = await backend.calls.count
        try await Task.sleep(for: .milliseconds(100))
        #expect(await backend.calls.count <= callsAtCancel + 1)
    }
}
