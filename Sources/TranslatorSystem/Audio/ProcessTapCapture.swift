import AVFAudio
import CoreAudio
import Foundation

public enum CaptureError: Error {
    case noAudioProcesses
    case tapCreationFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case permissionDenied
}

/// Captures one browser's audio (main app + helpers) through a Core Audio
/// process tap. The browser keeps playing to the speakers.
public final class ProcessTapCapture: @unchecked Sendable {
    private let browser: Browser
    private let ioQueue = DispatchQueue(label: "ProcessTapCapture.io", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    public private(set) var naturalFormat: AVAudioFormat?

    public init(browser: Browser) {
        self.browser = browser
    }

    deinit { stop() }

    public func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        stop()
        // Re-read every time: Chrome starts its audio helper lazily.
        let processes = BrowserAudioProcesses.matching(
            try BrowserAudioProcesses.allAudioProcesses(),
            browserBundleID: browser.bundleID
        )
        guard !processes.isEmpty else { throw CaptureError.noAudioProcesses }

        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw CaptureError.tapCreationFailed(status) }
        tapID = tap

        var streamDescription = try CoreAudioProperty.read(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            stop()
            throw CaptureError.tapCreationFailed(kAudioHardwareUnspecifiedError)
        }
        naturalFormat = format

        // Apple's tap sample uses the default output device as the main sub-device
        // so the aggregate device has a clock.
        let outputDevice = try CoreAudioProperty.read(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDefaultSystemOutputDevice,
            initial: AudioObjectID(kAudioObjectUnknown)
        )
        let outputUID = try CoreAudioProperty.readString(outputDevice, kAudioDevicePropertyDeviceUID) ?? ""
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "EarningsTranslator Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else {
            stop()
            throw CaptureError.aggregateDeviceFailed(status)
        }
        aggregateID = device

        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self, bufferingPolicy: .bufferingNewest(256))
        self.continuation = continuation
        let bytesPerFrame = streamDescription.mBytesPerFrame

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, ioQueue) { _, inputData, _, _, _ in
            guard let copy = Self.copyBuffer(inputData, format: format, bytesPerFrame: bytesPerFrame) else { return }
            continuation.yield(copy)
        }
        guard status == noErr else {
            stop()
            throw CaptureError.aggregateDeviceFailed(status)
        }
        status = AudioDeviceStart(device, procID)
        guard status == noErr else {
            stop()
            throw CaptureError.aggregateDeviceFailed(status)
        }
        return stream
    }

    public func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        continuation?.finish()
        continuation = nil
    }

    /// The IO buffer is reused by Core Audio after the callback, so copy it out.
    private static func copyBuffer(
        _ input: UnsafePointer<AudioBufferList>,
        format: AVAudioFormat,
        bytesPerFrame: UInt32
    ) -> AVAudioPCMBuffer? {
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = source.first, bytesPerFrame > 0 else { return nil }
        let frames = first.mDataByteSize / bytesPerFrame
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let destination = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let src = from.mData, let dst = to.mData else { continue }
            memcpy(dst, src, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return buffer
    }
}

// Captured buffers are freshly allocated copies, handed off once and never
// mutated afterwards, so passing them across tasks is safe.
extension AVAudioPCMBuffer: @retroactive @unchecked Sendable {}
