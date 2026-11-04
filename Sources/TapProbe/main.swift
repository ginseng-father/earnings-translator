import AVFAudio
import Foundation
import TranslatorSystem

// Usage: TapProbe <browser-bundle-id> <seconds> <output.wav>
let arguments = CommandLine.arguments
guard arguments.count == 4, let seconds = Double(arguments[2]) else {
    print("usage: TapProbe <browser-bundle-id> <seconds> <output.wav>")
    exit(2)
}
let result = await TapProbe.run(bundleID: arguments[1], seconds: seconds, output: URL(fileURLWithPath: arguments[3]))
exit(result)
