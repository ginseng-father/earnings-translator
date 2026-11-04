@preconcurrency import AVFAudio
import CoreMedia
import Foundation
import Speech

public enum TranscriptEvent: Sendable, Equatable {
    /// Words heard so far for the sentence in progress; replaced by the next event.
    case volatile(String)
    /// A finished result. `start` is seconds since audio began.
    case final(text: String, start: TimeInterval)
    case assetDownload(progress: Double)
}

public enum TranscriberError: Error {
    case localeUnsupported
    case assetsUnavailable
}

/// On-device English transcription with SpeechAnalyzer + SpeechTranscriber.
public final class LiveTranscriber: @unchecked Sendable {
    private let locale: Locale
    private let vocabulary: [String]
    private var analyzer: SpeechAnalyzer?
    private var inputSink: AsyncStream<AnalyzerInput>.Continuation?
    private var tasks: [Task<Void, Never>] = []
    private var finished = false

    /// `vocabulary` biases recognition toward domain words (EPS, guidance, …).
    public init(locale: Locale = Locale(identifier: "en-US"), vocabulary: [String] = []) {
        self.locale = locale
        self.vocabulary = vocabulary
    }

    private func makeModule() -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    /// Ensures the speech model for `locale` is installed, reporting download progress 0…1.
    public func prepare() -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [locale] in
                do {
                    guard await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil else {
                        throw TranscriberError.localeUnsupported
                    }
                    let module = SpeechTranscriber(locale: locale, preset: .transcription)
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                        let progress = request.progress
                        let reporter = Task {
                            while !Task.isCancelled {
                                continuation.yield(progress.fractionCompleted)
                                try? await Task.sleep(for: .milliseconds(500))
                            }
                        }
                        defer { reporter.cancel() }
                        try await request.downloadAndInstall()
                    }
                    continuation.yield(1)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Transcribes `audio` until it ends or `stop()` is called. The returned
    /// stream finishes once the last final result has been delivered.
    public func start(audio: AsyncStream<AVAudioPCMBuffer>, naturalFormat: AVAudioFormat?) -> AsyncStream<TranscriptEvent> {
        let (events, eventSink) = AsyncStream.makeStream(of: TranscriptEvent.self)
        let (input, inputSink) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputSink = inputSink
        finished = false

        let module = makeModule()
        let context = AnalysisContext()
        if !vocabulary.isEmpty {
            context.contextualStrings[.general] = vocabulary
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer

        let results = Task {
            do {
                for try await result in module.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if result.isFinal {
                        if !text.isEmpty { eventSink.yield(.final(text: text, start: result.range.start.seconds)) }
                    } else {
                        eventSink.yield(.volatile(text))
                    }
                }
            } catch {}
            eventSink.finish()
        }

        let feeder = Task { [weak self] in
            do {
                let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module], considering: naturalFormat)
                try await analyzer.setContext(context)
                try await analyzer.prepareToAnalyze(in: format)
                try await analyzer.start(inputSequence: input)
                var converter: BufferConverter?
                for await buffer in audio {
                    guard let format else { inputSink.yield(AnalyzerInput(buffer: buffer)); continue }
                    if converter == nil || converter?.input != buffer.format {
                        converter = BufferConverter(from: buffer.format, to: format)
                    }
                    if let converted = converter?.convert(buffer) {
                        inputSink.yield(AnalyzerInput(buffer: converted))
                    }
                }
            } catch {}
            await self?.finishInput()
        }
        tasks = [results, feeder]
        return events
    }

    /// Flushes pending audio into final results and ends the event stream.
    public func stop() async {
        await finishInput()
        for task in tasks { await task.value }
        tasks = []
        analyzer = nil
    }

    private func finishInput() async {
        guard !finished, let analyzer else { return }
        finished = true
        inputSink?.finish()
        inputSink = nil
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            await analyzer.cancelAndFinishNow()
        }
    }
}

/// Resamples/re-channels captured buffers into the analyzer's format.
private final class BufferConverter {
    let input: AVAudioFormat
    private let output: AVAudioFormat
    private let converter: AVAudioConverter?

    init(from input: AVAudioFormat, to output: AVAudioFormat) {
        self.input = input
        self.output = output
        converter = input == output ? nil : AVAudioConverter(from: input, to: output)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = output.sampleRate / input.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let result = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: result, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, result.frameLength > 0 else { return nil }
        return result
    }
}
