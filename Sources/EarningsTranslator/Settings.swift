import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@MainActor @Observable
final class Settings {
    /// Chosen in docs/model-bench.md.
    static let defaultModel = "gemma4:12b"
    static let models = ["gemma4:e4b", "gemma4:12b", "gemma4:26b"]

    private let defaults = UserDefaults.standard

    var modelTag: String {
        didSet { defaults.set(modelTag, forKey: "modelTag") }
    }

    var saveFolder: URL? {
        didSet { defaults.set(saveFolder?.path, forKey: "saveFolderPath") }
    }

    var pinOnTop: Bool {
        didSet { defaults.set(pinOnTop, forKey: "pinOnTop") }
    }

    init() {
        let stored = defaults.string(forKey: "modelTag")
        modelTag = stored.flatMap { Self.models.contains($0) ? $0 : nil } ?? Self.defaultModel
        saveFolder = defaults.string(forKey: "saveFolderPath").map { URL(fileURLWithPath: $0, isDirectory: true) }
        pinOnTop = defaults.object(forKey: "pinOnTop") as? Bool ?? true
    }
}
