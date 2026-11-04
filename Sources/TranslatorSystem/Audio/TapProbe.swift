import AVFAudio
import Foundation

/// Captures a few seconds of a browser's audio to a WAV file and reports the
/// peak level. Used by the TapProbe CLI and the app's hidden `--probe` flag.
public enum TapProbe {
    public static func run(bundleID: String, seconds: Double, output: URL) async -> Int32 {
        let processes = (try? BrowserAudioProcesses.allAudioProcesses()) ?? []
        let matched = BrowserAudioProcesses.matching(processes, browserBundleID: bundleID)
        print("matched audio processes: \(matched.count) of \(processes.count)")

        let capture = ProcessTapCapture(browser: Browser(bundleID: bundleID, name: bundleID))
        let stream: AsyncStream<AVAudioPCMBuffer>
        do {
            stream = try capture.start()
        } catch {
            print("capture failed: \(error)")
            return 1
        }
        guard let format = capture.naturalFormat,
              let file = try? AVAudioFile(forWriting: output, settings: format.settings,
                                          commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        else {
            print("cannot open \(output.path)")
            capture.stop()
            return 1
        }
        print("format: \(format)")

        let stopper = Task {
            try? await Task.sleep(for: .seconds(seconds))
            capture.stop()
        }
        var peak: Float = 0
        var frames: AVAudioFrameCount = 0
        for await buffer in stream {
            try? file.write(from: buffer)
            frames += buffer.frameLength
            peak = max(peak, Self.peak(of: buffer))
        }
        stopper.cancel()
        print(String(format: "frames: %u, peak: %.4f", frames, peak))
        return peak > 0.01 ? 0 : 3
    }

    public static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        let stride = buffer.stride
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(channels[channel][frame * stride]))
            }
        }
        return peak
    }
}
