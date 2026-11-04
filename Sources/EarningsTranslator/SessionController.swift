import AppKit
import AVFAudio
import Observation
import TranslatorCore
import TranslatorSystem

enum Banner: Equatable {
    case ollamaUnreachable
    case modelMissing(String)
    case translationDelayed(Int)
    case permissionDenied
    case speechPermissionDenied
    case speechUnavailable
    case speechAssetDownloading(Double)
    case noBrowserAudio(String)
    case saveFailed(String)
    case browserQuit
}

/// Wires capture → transcription → translation → transcript for one session.
@MainActor @Observable
final class SessionController {
    var segments: [Segment] = []
    var liveEnglish: String?
    var isRunning = false
    var browsers: [Browser] = []
    var selectedBrowser: Browser?
    var banner: Banner?
    let settings: Settings

    private var capture: ProcessTapCapture?
    private var transcriber: LiveTranscriber?
    private var queue: TranslationQueue?
    private var autosaver: TranscriptAutosaver?
    private var eventsTask: Task<Void, Never>?
    private var tasks: [Task<Void, Never>] = []
    private var indexByID: [UUID: Int] = [:]
    private var lastLoudAudio = Date.distantPast
    private var sessionStart: Date?
    private var currentFolder: URL?
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
        guard !isRunning, let browser = selectedBrowser else { return }
        guard let folder = settings.saveFolder ?? chooseFolder() else { return }
        banner = nil

        guard await SpeechAuthorization.request() else {
            banner = .speechPermissionDenied
            return
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
            return
        }

        let capture = ProcessTapCapture(browser: browser)
        let audio: AsyncStream<AVAudioPCMBuffer>
        do {
            audio = try capture.start()
        } catch CaptureError.noAudioProcesses {
            banner = .noBrowserAudio(browser.name)
            return
        } catch {
            banner = .permissionDenied
            return
        }

        let sessionStart = Date()
        self.sessionStart = sessionStart
        currentFolder = folder
        let queue = TranslationQueue(backend: backend, glossary: glossary)
        let autosaver = TranscriptAutosaver(folder: folder, sessionStart: sessionStart)
        self.capture = capture
        self.transcriber = transcriber
        self.queue = queue
        self.autosaver = autosaver
        segments = []
        indexByID = [:]
        liveEnglish = nil
        lastLoudAudio = .distantPast
        isRunning = true

        let events = transcriber.start(audio: meter(audio), naturalFormat: capture.naturalFormat)
        eventsTask = Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
        tasks = [
            Task { [weak self] in
                for await update in queue.updates { self?.apply(update) }
            },
            Task { [weak self] in
                for await health in queue.health { self?.show(health) }
            },
            Task { [weak self] in
                for await error in autosaver.errors { self?.banner = .saveFailed(error.localizedDescription) }
            },
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isRunning, self.lastLoudAudio == .distantPast else { return }
                self.banner = .permissionDenied
            },
        ]
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false
        capture?.stop()
        await transcriber?.stop()
        await eventsTask?.value
        await queue?.finish()
        // Let the update stream deliver the last results before the final save.
        try? await Task.sleep(for: .milliseconds(200))
        tasks.forEach { $0.cancel() }
        tasks = []
        liveEnglish = nil
        await autosaver?.update(segments)
        do {
            try await autosaver?.close()
        } catch {
            banner = .saveFailed(error.localizedDescription)
        }
        capture = nil
        transcriber = nil
        queue = nil
        eventsTask = nil
    }

    func saveNow() async {
        guard let autosaver else { return }
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
        guard let folder = chooseFolder() else { return }
        currentFolder = folder
        await autosaver?.setFolder(folder)
        await saveNow()
    }

    /// Synchronous last-chance save when the app quits mid-session.
    func saveOnQuit() {
        guard isRunning, let folder = currentFolder, let sessionStart else { return }
        let text = MarkdownExporter.render(segments: segments, sessionStart: sessionStart)
        let url = folder.appendingPathComponent(MarkdownExporter.fileName(for: sessionStart))
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    // MARK: Event handling

    private func handle(_ event: TranscriptEvent) {
        switch event {
        case .volatile(let text):
            liveEnglish = text.isEmpty ? nil : text
        case .final(let text, let start):
            liveEnglish = nil
            for chunk in SentenceSplitter.split(text) {
                let segment = Segment(start: start, english: chunk)
                indexByID[segment.id] = segments.count
                segments.append(segment)
                let queue = self.queue
                Task { await queue?.enqueue(segment) }
            }
            saveSoon()
        case .assetDownload:
            break
        }
    }

    private func apply(_ update: SegmentUpdate) {
        guard let index = indexByID[update.id] else { return }
        segments[index].status = update.status
        if let korean = update.korean { segments[index].korean = korean }
        saveSoon()
    }

    private func show(_ health: QueueHealth) {
        switch health {
        case .ok:
            switch banner {
            case .translationDelayed, .ollamaUnreachable: banner = nil
            default: break
            }
        case .delayed(let backlog): banner = .translationDelayed(backlog)
        case .offline: banner = .ollamaUnreachable
        }
    }

    private func saveSoon() {
        let snapshot = segments
        let autosaver = self.autosaver
        Task { await autosaver?.update(snapshot) }
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

    /// Passes audio through while noting when it was last audible.
    private func meter(_ audio: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                for await buffer in audio {
                    if TapProbe.peak(of: buffer) > 0.01 {
                        await MainActor.run {
                            self?.lastLoudAudio = Date()
                            if self?.banner == .permissionDenied { self?.banner = nil }
                        }
                    }
                    continuation.yield(buffer)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
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
