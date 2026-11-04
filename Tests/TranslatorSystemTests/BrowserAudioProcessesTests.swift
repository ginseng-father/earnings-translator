import Testing
@testable import TranslatorSystem

struct BrowserAudioProcessesTests {
    @Test func matchesMainAndHelperBundleIDs() {
        let all = [
            AudioProcessInfo(objectID: 1, pid: 10, bundleID: "com.google.Chrome"),
            AudioProcessInfo(objectID: 2, pid: 11, bundleID: "com.google.Chrome.helper"),
            AudioProcessInfo(objectID: 3, pid: 12, bundleID: "com.google.Chrome.helper.renderer"),
            AudioProcessInfo(objectID: 4, pid: 13, bundleID: "com.apple.Safari"),
            AudioProcessInfo(objectID: 5, pid: 14, bundleID: nil),
        ]
        #expect(BrowserAudioProcesses.matching(all, browserBundleID: "com.google.Chrome") == [1, 2, 3])
    }

    @Test func doesNotMatchSimilarPrefix() {
        let all = [AudioProcessInfo(objectID: 7, pid: 20, bundleID: "com.google.ChromeCanary")]
        #expect(BrowserAudioProcesses.matching(all, browserBundleID: "com.google.Chrome").isEmpty)
    }
}
