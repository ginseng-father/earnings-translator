import AppKit
import AVFAudio
import Observation
import TranslatorCore
import TranslatorSystem

enum Banner: Equatable {
    case ollamaUnreachable
    case modelMissing(String)
    case translationDelayed(Int)
    case translationFailing
    case permissionDenied
    case speechPermissionDenied
    case speechUnavailable
    case speechAssetDownloading(Double)
    case noBrowserAudio(String)
    case audioStopped
    case transcriptionStopped
    case saveFailed(String)
    case browserQuit
}

/// Everything one session owns, so `stop()` tears down exactly that session
/// even if another one is started right after.
private struct Session {
    let capture: ProcessTapCapture
    let transcriber: LiveTranscriber
    let queue: TranslationQueue
    let autosaver: TranscriptAutosaver
    let start: Date
    var folder: URL
    var eventsTask: Task<Void, Never>?
    var updatesTask: Task<Void, Never>?
    var tasks: [Task<Void, Never>] = []
}

/// Wires capture → transcription → translation → transcript for one session.
@MainActor @Observable
final class SessionController {
    var segments: [Segment] = []
    var liveEnglish: String?
    var browsers: [Browser] = []
    var selectedBrowser: Browser?
    var banner: Banner?
    let settings: Settings

    private var gate = SessionGate()
    var isRunning: Bool { gate.phase == .running }
    /// Starting or stopping: the start/stop button is disabled meanwhile.
    var isBusy: Bool { gate.phase == .starting || gate.phase == .stopping }

    private var session: Session?
    private var indexByID: [UUID: Int] = [:]
    private var heardAudio = false
    private var stall = StallDetector(timeout: 10)
    private var quitObserver: NSObjectProtocol?

    init(settings: Settings) {
        self.settings = settings
        refreshBrowsers()
        quitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.browserTerminated(bundleID) }
        }
    }

    func refreshBrowsers() {
        browsers = BrowserAudioProcesses.runningBrowsers()
        if selectedBrowser == nil || !browsers.contains(selectedBrowser!) {
            selectedBrowser = browsers.first { $0.bundleID == "com.google.Chrome" } ?? browsers.first
        }
    }

    // MARK: Session

    func start() async {
        guard let browser = selectedBrowser, gate.beginStart() else { return }
        let started = await startSession(browser: browser)
        gate.finishStart(running: started)
    }

    private func startSession(browser: Browser) async -> Bool {
        guard let folder = settings.saveFolder ?? chooseFolder() else { return false }
        banner = nil

        guard await SpeechAuthorization.request() else {
            banner = .speechPermissionDenied
            return false
        }

        let glossary = loadGlossary()
        let backend = OllamaClient(model: settings.modelTag, glossary: glossary)
        switch await backend.health() {
        case .ok: break
        case .unreachable: banner = .ollamaUnreachable
        case .modelMissing(let model): banner = .modelMissing(model)
        }

        let transcriber = LiveTranscriber(vocabulary: glossary.entries.flatMap(\.english))
        do {
            for try await progress in transcriber.prepare() where progress < 1 {
                banner = .speechAssetDownloading(progress)
            }
            if case .speechAssetDownloading = banner { banner = nil }
        } catch {
            banner = .speechUnavailable
            return false
        }

        let capture = ProcessTapCapture(browser: browser)
        let audio: AsyncStream<AVAudioPCMBuffer>
        do {
            audio = try capture.start()
        } catch CaptureError.noAudioProcesses {
            banner = .noBrowserAudio(browser.name)
            return false
        } catch {
            banner = .permissionDenied
            return false
        }

        let start = Date()
        let queue = TranslationQueue(backend: backend, glossary: glossary)
        let autosaver = TranscriptAutosaver(folder: folder, sessionStart: start)
        var session = Session(capture: capture, transcriber: transcriber, queue: queue, autosaver: autosaver, start: start, folder: folder)
        segments = []
        indexByID = [:]
        liveEnglish = nil
        heardAudio = false
        stall = StallDetector(timeout: 10, startedAt: start)

        let events = transcriber.start(audio: meter(audio), naturalFormat: capture.naturalFormat)
        session.eventsTask = Task { [weak self] in
            for await event in events { await self?.handle(event, queue: queue, autosaver: autosaver) }
            // The stream only ends on its own if recognition failed mid-session.
            if let self, self.isRunning, self.session?.queue === queue { self.banner = .transcriptionStopped }
        }
        session.updatesTask = Task { [weak self] in
            for await update in queue.updates { self?.apply(update, autosaver: autosaver) }
        }
        session.tasks = [
            Task { [weak self] in
                for await health in queue.health { self?.show(health) }
            },
            Task { [weak self] in
                for await error in autosaver.errors { self?.banner = .saveFailed(error.localizedDescription) }
            },
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isRunning, !self.heardAudio else { return }
                self.banner = .permissionDenied
            },
            Task { [weak self] in
                // Buffers keep arriving during silence; none for 10 s means the
                // capture died (output device changed, browser audio helper gone).
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard let self, self.isRunning else { return }
                    if self.stall.isStalled() { self.banner = .audioStopped }
                }
            },
        ]
        self.session = session
        return true
    }

    func stop() async {
        guard gate.beginStop(), let session else { return }
        session.capture.stop()
        await session.transcriber.stop()
        await session.eventsTask?.value
        await session.queue.finish()
        // finish() returns early while Ollama is offline; cancel() stops retrying for
        // good and ends the update stream, so the consumer below drains and exits.
        // Untranslated lines are saved as "(번역 대기 중)".
        await session.queue.cancel()
        await session.updatesTask?.value
        session.tasks.forEach { $0.cancel() }
        liveEnglish = nil
        await session.autosaver.update(segments)
        do {
            try await session.autosaver.close()
        } catch {
            banner = .saveFailed(error.localizedDescription)
        }
        self.session = nil
        gate.finishStop()
    }

    func saveNow() async {
        guard let autosaver = session?.autosaver else { return }
        await autosaver.update(segments)
        do {
            try await autosaver.flush()
            if case .saveFailed = banner { banner = nil }
        } catch {
            banner = .saveFailed(error.localizedDescription)
        }
    }

    /// Lets the user pick a new folder after a failed save, then saves there.
    func chooseNewSaveFolder() async {
        guard session != nil, let folder = chooseFolder() else { return }
        session?.folder = folder
        await session?.autosaver.setFolder(folder)
        await saveNow()
    }

    /// Synchronous last-chance save when the app quits mid-session.
    func saveOnQuit() {
        guard let session else { return }
        let text = MarkdownExporter.render(segments: segments, sessionStart: session.start)
        let url = session.folder.appendingPathComponent(MarkdownExporter.fileName(for: session.start))
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    // MARK: Event handling

    private func handle(_ event: TranscriptEvent, queue: TranslationQueue, autosaver: TranscriptAutosaver) async {
        switch event {
        case .volatile(let text):
            liveEnglish = text.isEmpty ? nil : text
        case .final(let text, let start):
            liveEnglish = nil
            for chunk in SentenceSplitter.split(text) {
                let segment = Segment(start: start, english: chunk)
                indexByID[segment.id] = segments.count
                segments.append(segment)
                // Awaited in the events loop, so sentences reach the queue in order
                // and all of them before stop() calls finish().
                await queue.enqueue(segment)
            }
            save(to: autosaver)
            if banner == .transcriptionStopped { banner = nil }
        case .assetDownload:
            break
        }
    }

    private func apply(_ update: SegmentUpdate, autosaver: TranscriptAutosaver) {
        guard let index = indexByID[update.id], index < segments.count, segments[index].id == update.id else { return }
        segments[index].status = update.status
        if let korean = update.korean { segments[index].korean = korean }
        save(to: autosaver)
    }

    private func show(_ health: QueueHealth) {
        switch health {
        case .ok:
            switch banner {
            case .translationDelayed, .ollamaUnreachable, .modelMissing, .translationFailing: banner = nil
            default: break
            }
        case .delayed(let backlog): banner = .translationDelayed(backlog)
        case .offline: banner = .ollamaUnreachable
        case .failing: banner = .translationFailing
        }
    }

    private func save(to autosaver: TranscriptAutosaver) {
        let snapshot = segments
        Task { await autosaver.update(snapshot) }
    }

    private func browserTerminated(_ bundleID: String?) {
        let wasCapturing = isRunning && bundleID != nil && bundleID == selectedBrowser?.bundleID
        refreshBrowsers()
        guard wasCapturing else { return }
        Task {
            await stop()
            banner = .browserQuit
        }
    }

    /// Passes audio through off the main actor, reporting once a second that
    /// buffers are still arriving and whether any were audible.
    private func meter(_ audio: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            let task = Task.detached { [weak self] in
                var lastReport = ContinuousClock.now
                var loud = false
                for await buffer in audio {
                    loud = loud || TapProbe.peak(of: buffer) > 0.01
                    continuation.yield(buffer)
                    if ContinuousClock.now - lastReport >= .seconds(1) {
                        lastReport = .now
                        let heard = loud
                        loud = false
                        await self?.audioHeartbeat(loud: heard)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func audioHeartbeat(loud: Bool) {
        stall.feed()
        if banner == .audioStopped { banner = nil }
        if loud {
            heardAudio = true
            if banner == .permissionDenied { banner = nil }
        }
    }

    // MARK: Helpers

    private func loadGlossary() -> Glossary {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EarningsTranslator", isDirectory: true)
        let url = directory.appendingPathComponent("glossary.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? Glossary.standard.save(to: url)
        }
        return (try? Glossary.load(from: url)) ?? .standard
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "번역 대본을 저장할 폴더를 고르세요."
        panel.prompt = "선택"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        settings.saveFolder = url
        return url
    }
}
