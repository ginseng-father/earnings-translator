import Foundation
import Testing
@testable import TranslatorCore

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("autosave-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct TranscriptAutosaverTests {
    @Test func flushWritesRenderedTranscript() async throws {
        let folder = try makeTempDirectory()
        let saver = TranscriptAutosaver(folder: folder, sessionStart: sessionStart(), interval: .seconds(60))
        await saver.update(sampleSegments())
        try await saver.flush()
        let url = await saver.fileURL
        #expect(url.lastPathComponent == "2026-11-04_1830.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == MarkdownExporter.render(segments: sampleSegments(), sessionStart: sessionStart()))
    }

    @Test func unchangedFlushDoesNotRewrite() async throws {
        let folder = try makeTempDirectory()
        let saver = TranscriptAutosaver(folder: folder, sessionStart: sessionStart(), interval: .seconds(60))
        await saver.update(sampleSegments())
        try await saver.flush()
        try FileManager.default.removeItem(at: await saver.fileURL)
        try await saver.flush()
        #expect(!FileManager.default.fileExists(atPath: await saver.fileURL.path))
    }

    @Test func timerSavesWithoutExplicitFlush() async throws {
        let folder = try makeTempDirectory()
        let saver = TranscriptAutosaver(folder: folder, sessionStart: sessionStart(), interval: .milliseconds(20))
        await saver.update(sampleSegments())
        try await Task.sleep(for: .milliseconds(300))
        #expect(FileManager.default.fileExists(atPath: await saver.fileURL.path))
    }

    @Test func autosaveFailureKeepsDirtyAndReportsError() async throws {
        let folder = try makeTempDirectory()
        try FileManager.default.removeItem(at: folder)
        let saver = TranscriptAutosaver(folder: folder, sessionStart: sessionStart(), interval: .seconds(60))
        await saver.update(sampleSegments())
        await #expect(throws: (any Error).self) { try await saver.flush() }

        let replacement = try makeTempDirectory()
        await saver.setFolder(replacement)
        try await saver.flush()
        let url = await saver.fileURL
        #expect(url.deletingLastPathComponent().standardizedFileURL == replacement.standardizedFileURL)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("Thank you."))
    }

    @Test func timerFailureIsReported() async throws {
        let folder = try makeTempDirectory()
        try FileManager.default.removeItem(at: folder)
        let saver = TranscriptAutosaver(folder: folder, sessionStart: sessionStart(), interval: .milliseconds(20))
        await saver.update(sampleSegments())
        var iterator = saver.errors.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }
}
