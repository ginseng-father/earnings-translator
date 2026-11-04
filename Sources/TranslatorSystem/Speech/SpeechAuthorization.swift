import Speech

public enum SpeechAuthorization {
    /// Nonisolated on purpose: TCC calls back on a background queue, and a
    /// main-actor closure here would trap on the isolation check.
    public static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }
}
