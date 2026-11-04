import AVFAudio
import Foundation

/// Transcribes an audio file through `LiveTranscriber` and prints each final
/// result. Speech recognition only works inside an app bundle that declares
/// `NSSpeechRecognitionUsageDescription`, so this runs from the app's hidden
/// `--transcribe-file <path>` flag rather than from `swift test`.
public enum TranscribeProbe {
    public static func run(file url: URL) async -> Int32 {
        print("speech authorized: \(await SpeechAuthorization.request())")

        let transcriber = LiveTranscriber()
        do {
            for try await _ in transcriber.prepare() {}
        } catch {
            print("prepare failed: \(error)")
            return 1
        }
        guard let file = try? AVAudioFile(forReading: url) else {
            print("cannot read \(url.path)")
            return 1
        }
        let format = file.processingFormat
        let (audio, sink) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        while file.framePosition < file.length,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096),
              (try? file.read(into: buffer)) != nil {
            sink.yield(buffer)
        }
        sink.finish()

        var finals = 0
        for await event in transcriber.start(audio: audio, naturalFormat: format) {
            if case .final(let text, let start) = event {
                finals += 1
                print(String(format: "FINAL [%.2f] %@", start, text))
            }
        }
        return finals > 0 ? 0 : 3
    }
}
