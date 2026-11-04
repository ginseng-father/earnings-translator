import AppKit
import CoreAudio

public struct AudioProcessInfo: Sendable, Equatable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String?

    public init(objectID: AudioObjectID, pid: pid_t, bundleID: String?) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
    }
}

public struct Browser: Sendable, Hashable, Identifiable {
    public let bundleID: String
    public let name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public enum BrowserAudioProcesses {
    public static let knownBrowsers: [Browser] = [
        Browser(bundleID: "com.google.Chrome", name: "Chrome"),
        Browser(bundleID: "com.apple.Safari", name: "Safari"),
        Browser(bundleID: "company.thebrowser.Browser", name: "Arc"),
        Browser(bundleID: "com.microsoft.edgemac", name: "Edge"),
        Browser(bundleID: "org.mozilla.firefox", name: "Firefox"),
        Browser(bundleID: "com.naver.Whale", name: "Whale"),
    ]

    /// Audio process objects that belong to the browser: the app itself and
    /// its helpers (`<bundleID>.<anything>`), which is where Chrome plays sound.
    public static func matching(_ all: [AudioProcessInfo], browserBundleID: String) -> [AudioObjectID] {
        all.filter { process in
            guard let id = process.bundleID else { return false }
            return id == browserBundleID || id.hasPrefix(browserBundleID + ".")
        }
        .map(\.objectID)
    }

    public static func allAudioProcesses() throws -> [AudioProcessInfo] {
        let objects = try CoreAudioProperty.readArray(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyProcessObjectList,
            initial: AudioObjectID(kAudioObjectUnknown)
        )
        return objects.map { object in
            let pid = (try? CoreAudioProperty.read(object, kAudioProcessPropertyPID, initial: pid_t(-1))) ?? -1
            let bundleID = (try? CoreAudioProperty.readString(object, kAudioProcessPropertyBundleID)) ?? nil
            return AudioProcessInfo(objectID: object, pid: pid, bundleID: bundleID)
        }
    }

    public static func runningBrowsers() -> [Browser] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return knownBrowsers.filter { running.contains($0.bundleID) }
    }
}
