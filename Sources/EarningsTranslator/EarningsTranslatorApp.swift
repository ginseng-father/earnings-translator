import SwiftUI
import TranslatorSystem

@main
struct EarningsTranslatorApp: App {
    init() {
        Self.runDiagnosticFlagIfPresent()
    }

    var body: some Scene {
        WindowGroup {
            Text("EarningsTranslator")
                .frame(minWidth: 320, minHeight: 400)
        }
        .defaultSize(width: 420, height: 800)
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
