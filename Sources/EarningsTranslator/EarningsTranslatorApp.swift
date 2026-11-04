import AppKit
import SwiftUI
import TranslatorSystem

@main
struct EarningsTranslatorApp: App {
    // Plain stored references rather than @State: SwiftUI's @State is a macro in
    // this SDK and its plugin ships only with Xcode, not the Command Line Tools.
    // The App value is created once, and @Observable drives view updates.
    private let settings: Settings
    private let session: SessionController
    private let scroll = TranscriptScrollState()

    init() {
        Self.runDiagnosticFlagIfPresent()
        let settings = Settings()
        self.settings = settings
        session = SessionController(settings: settings)
    }

    var body: some Scene {
        Window("EarningsTranslator", id: "transcript") {
            ContentView(session: session, settings: settings, scroll: scroll)
                .frame(minWidth: 320, minHeight: 400)
        }
        .defaultSize(width: 420, height: 800)
        // Always open the transcript window, even if it was closed when the
        // app last quit (scene restoration would otherwise keep it closed).
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
    }

    /// Hidden diagnostics that need the app bundle's privacy strings:
    /// `--probe <bundle-id> <seconds> <out.wav>` and `--transcribe-file <path>`.
    private static func runDiagnosticFlagIfPresent() {
        let arguments = CommandLine.arguments
        let job: (@Sendable () async -> Int32)?
        if let i = arguments.firstIndex(of: "--probe"), arguments.count > i + 3, let seconds = Double(arguments[i + 2]) {
            let bundleID = arguments[i + 1], output = URL(fileURLWithPath: arguments[i + 3])
            job = { await TapProbe.run(bundleID: bundleID, seconds: seconds, output: output) }
        } else if let i = arguments.firstIndex(of: "--transcribe-file"), arguments.count > i + 1 {
            let file = URL(fileURLWithPath: arguments[i + 1])
            job = { await TranscribeProbe.run(file: file) }
        } else {
            job = nil
        }
        guard let job else { return }
        Task.detached {
            let code = await job()
            exit(code)
        }
        dispatchMain()
    }
}

struct ContentView: View {
    @Bindable var session: SessionController
    @Bindable var settings: Settings
    let scroll: TranscriptScrollState

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(session: session, settings: settings)
            Divider()
            if let banner = session.banner {
                StatusBanner(banner: banner) {
                    Task { await session.chooseNewSaveFolder() }
                }
                Divider()
            }
            TranscriptView(segments: session.segments, liveEnglish: session.liveEnglish, sessionActive: session.isRunning, scroll: scroll)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            applyPin()
            runAutostartIfRequested()
        }
        .onChange(of: settings.pinOnTop) { applyPin() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            session.refreshBrowsers()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.saveOnQuit()
        }
    }

    /// Hidden end-to-end check driven by environment variables
    /// (`open --env ET_AUTOSTART_SECONDS=… --env ET_AUTOSTART_FOLDER=…`): starts a
    /// session on the default browser, stops after the given seconds, and quits.
    /// Not launch arguments: AppKit treats a path argument as a document to open
    /// and then skips the main window.
    private func runAutostartIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let seconds = environment["ET_AUTOSTART_SECONDS"].flatMap(Double.init),
              let folder = environment["ET_AUTOSTART_FOLDER"] else { return }
        settings.saveFolder = URL(fileURLWithPath: folder, isDirectory: true)
        Task {
            await session.start()
            print("autostart: running=\(session.isRunning) banner=\(String(describing: session.banner))")
            try? await Task.sleep(for: .seconds(seconds))
            print("autostart: before stop banner=\(String(describing: session.banner)) segments=\(session.segments.count)")
            await session.stop()
            let flagged = session.segments.filter { if case .flagged = $0.status { true } else { false } }.count
            let untranslated = session.segments.filter { $0.korean == nil }.count
            print("autostart: segments=\(session.segments.count) flagged=\(flagged) untranslated=\(untranslated)")
            NSApplication.shared.terminate(nil)
        }
    }

    /// Pinned: floats above other windows, follows every desktop, and shows
    /// over a full-screen browser. Unpinned: an ordinary window that Mission
    /// Control can move to a single desktop.
    private func applyPin() {
        for window in NSApplication.shared.windows where window.canBecomeMain {
            if settings.pinOnTop {
                window.level = .floating
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            } else {
                window.level = .normal
                window.collectionBehavior = [.managed, .participatesInCycle]
            }
        }
    }
}
