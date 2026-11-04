# Earnings Call Translator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app that taps Chrome's audio, transcribes English on-device, translates each sentence to Korean with local Gemma 4 via Ollama, verifies numbers and earnings terms, and shows/saves a side-window transcript.

**Architecture:** One SwiftPM package. `TranslatorCore` holds all pure, unit-tested logic (number extraction, validation, glossary, prompt/Ollama client, translation queue, sentence splitting, Markdown export). `TranslatorSystem` wraps OS APIs (Core Audio process tap, SpeechAnalyzer). `EarningsTranslator` is the SwiftUI app; `TapProbe` and `TranslateBench` are small CLIs used to de-risk capture and choose the model. A script assembles the `.app` bundle because Xcode is not installed.

**Tech Stack:** Swift 6.4 (CLT toolchain), SwiftPM, SwiftUI, Swift Testing (`import Testing`), Core Audio (`AudioHardwareCreateProcessTap`, `CATapDescription`), Speech (`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`), AVFAudio, URLSession → Ollama `http://localhost:11434`.

**Spec:** `docs/superpowers/specs/2026-11-04-earnings-call-translator-design.md` (Korean). Read it before any task.

## Global Constraints

- Platform floor: `.macOS(.v26)`; swift-tools-version `6.2`; Swift 6 language mode (strict concurrency).
- No network calls except `http://localhost:11434` (Ollama) and Apple's speech-asset download. Never use the `gemma4:cloud` or `*-cloud` tags.
- Default model tag `gemma4:12b`; allowed in settings: `gemma4:e4b`, `gemma4:12b`, `gemma4:26b`. Task 6 may change the default.
- Ollama request options: `temperature: 0`, `keep_alive: "2h"`, `stream: false`.
- Speech locale `en-US`.
- Long-sentence split threshold: more than 40 words.
- Autosave interval 5 s; transcript filename `yyyy-MM-dd_HHmm.md` (session start, local time); per-line timestamp `HH:MM:SS` measured from session start.
- Every sentence must eventually be translated. Batch queued sentences, never drop them.
- ⚠ means "the translation may differ from the English transcript". Tooltip copy (exact): `번역의 숫자나 용어가 영어 원문과 다를 수 있습니다. 영어 받아쓰기 자체의 오류는 검사하지 않습니다.`
- UI copy is Korean. Dark mode must work (use semantic system colors).
- Bundle id `local.earningstranslator`, app name `EarningsTranslator`. Info.plist must carry `NSAudioCaptureUsageDescription` and `NSSpeechRecognitionUsageDescription`.
- The repo is not a git repo yet. Task 0 runs `git init`. Commit after every task. Add `.superpowers/` and `.build/` to `.gitignore`.

## Review Focus

1. **Ollama returns malformed JSON, or a batch reply with the wrong number of items or ids.** Expect no crash and no lost sentence: fall back to translating each sentence on its own. Test in Task 7: `batchReplyWithWrongCountFallsBackToSingles`.
2. **Long silence or hold music, or a gap of minutes with no speech.** Expect capture and transcription to stay alive and resume when speech returns, with nothing stuck "translating". Test in Task 7 (`queueIdlesAndResumes`) plus a manual check in Task 11.
3. **Ranges, negatives and repeated numbers** ("$1.60 to $1.65", "down 3%", "3% … 3%"). Expect a multiset comparison: both bounds checked, the same value counted twice when it appears twice, and sign words ignored. Tests in Tasks 2–4: `extractsRangeBothEnds`, `repeatedValuesAreCounted`.
4. **Model adds commentary, leaves English untranslated, or returns an empty string.** Expect the result to be treated as a validation failure: retry once, then ⚠. An empty string is never shown as done. Test in Task 7: `emptyTranslationIsFlagged`.
5. **Save folder deleted or unwritable mid-session.** Expect the in-memory transcript to survive, a visible error banner, and a successful retry once a new folder is chosen. Test in Task 9: `autosaveFailureKeepsDirtyAndReportsError`.

---

## File Structure

```
Package.swift
Resources/Info.plist
scripts/build-app.sh                       # swift build + assemble + ad-hoc sign .app
Sources/TranslatorCore/
  Model/Segment.swift                      # Segment, SegmentStatus
  Numbers/Quantity.swift                   # Quantity, QuantityUnit
  Numbers/EnglishQuantityExtractor.swift
  Numbers/KoreanQuantityExtractor.swift
  Glossary/Glossary.swift                  # GlossaryEntry, Glossary (default + JSON load)
  Validation/TranslationValidator.swift    # ValidationIssue, TranslationValidator
  Translation/PromptBuilder.swift
  Translation/OllamaClient.swift           # TranslationBackend protocol + Ollama impl
  Translation/TranslationQueue.swift       # actor: batching, retry, offline, lag
  Transcript/SentenceSplitter.swift
  Export/MarkdownExporter.swift
  Export/TranscriptAutosaver.swift
Sources/TranslatorSystem/
  Audio/BrowserAudioProcesses.swift        # find Chrome (+helpers) audio process objects
  Audio/ProcessTapCapture.swift            # tap + aggregate device → AsyncStream<AVAudioPCMBuffer>
  Speech/LiveTranscriber.swift             # SpeechAnalyzer wrapper → AsyncStream<TranscriptEvent>
Sources/TapProbe/main.swift                # CLI: capture N seconds of a browser to WAV
Sources/TranslateBench/main.swift          # CLI: run fixtures through models, report
Sources/EarningsTranslator/
  EarningsTranslatorApp.swift
  SessionController.swift                  # @MainActor @Observable orchestration
  Settings.swift                           # model tag, save folder, pin-on-top (UserDefaults)
  Views/TranscriptView.swift
  Views/SegmentRow.swift
  Views/ToolbarView.swift
  Views/StatusBanner.swift
Tests/TranslatorCoreTests/   (one file per Core unit; Fixtures/earnings-sentences.json)
Tests/TranslatorSystemTests/BrowserAudioProcessesTests.swift
Tests/TranslatorSystemTests/LiveTranscriberIntegrationTests.swift
docs/model-bench.md                        # Task 6 results
```

---

### Task 0: Package skeleton, app bundle script, empty window

**Files:**
- Create: `Package.swift`, `Resources/Info.plist`, `scripts/build-app.sh`, `.gitignore`, `Sources/EarningsTranslator/EarningsTranslatorApp.swift`, and placeholder files so every target compiles.

**Interfaces:**
- Produces: targets `TranslatorCore` (library), `TranslatorSystem` (library, depends on Core), executables `EarningsTranslator`, `TapProbe`, `TranslateBench` (all depend on System + Core), test targets `TranslatorCoreTests` (declares `resources: [.copy("Fixtures")]`), `TranslatorSystemTests`.
- `scripts/build-app.sh [debug|release]` → `build/EarningsTranslator.app` (`Contents/MacOS/EarningsTranslator`, `Contents/Info.plist`), signed with `codesign --force --sign -`.

- [ ] **Step 1:** `git init`. Write `.gitignore` (`.build/`, `build/`, `.superpowers/`, `.DS_Store`).
- [ ] **Step 2:** Write `Package.swift` with the targets above. Write `Info.plist` with `CFBundleIdentifier=local.earningstranslator`, `CFBundleExecutable=EarningsTranslator`, `LSMinimumSystemVersion=26.0`, `NSAudioCaptureUsageDescription="실적 발표를 번역하려면 브라우저 소리를 들어야 합니다."`, `NSSpeechRecognitionUsageDescription="영어 음성을 받아 적기 위해 사용합니다."`.
- [ ] **Step 3:** The app shows one `WindowGroup` with the text `EarningsTranslator`, default size 420×800.
- [ ] **Step 4:** Run `swift build && swift test && scripts/build-app.sh debug && open build/EarningsTranslator.app`. Expected: the build succeeds, `swift test` reports no failures, and the window appears. Note in the script header that ad-hoc re-signing makes macOS ask for permissions again after each rebuild.
- [ ] **Step 5:** Commit `chore: scaffold package and app bundle script`.

### Task 1: Chrome audio capture (highest risk — do first)

**Files:**
- Create: `Sources/TranslatorSystem/Audio/BrowserAudioProcesses.swift`, `Sources/TranslatorSystem/Audio/ProcessTapCapture.swift`, `Sources/TapProbe/main.swift`
- Test: `Tests/TranslatorSystemTests/BrowserAudioProcessesTests.swift`

**Interfaces:**
- Produces:
  - `public struct AudioProcessInfo: Sendable, Equatable { public let objectID: AudioObjectID; public let pid: pid_t; public let bundleID: String? }`
  - `public struct Browser: Sendable, Hashable, Identifiable { public let bundleID: String; public let name: String; public var id: String { bundleID } }`
  - `public enum BrowserAudioProcesses { public static func matching(_ all: [AudioProcessInfo], browserBundleID: String) -> [AudioObjectID]; public static func allAudioProcesses() throws -> [AudioProcessInfo]; public static func runningBrowsers() -> [Browser] }`
  - `public final class ProcessTapCapture: @unchecked Sendable { public init(browser: Browser); public func start() throws -> AsyncStream<AVAudioPCMBuffer>; public func stop(); public var naturalFormat: AVAudioFormat? { get } }`
  - `public enum CaptureError: Error { case noAudioProcesses, tapCreationFailed(OSStatus), aggregateDeviceFailed(OSStatus), permissionDenied }`

- [ ] **Step 1: Write the failing tests** for the pure matcher:
  - `matchesMainAndHelperBundleIDs`: processes with bundle ids `com.google.Chrome`, `com.google.Chrome.helper`, `com.google.Chrome.helper.renderer`, `com.apple.Safari`, `nil` → returns only the three Chrome object ids.
  - `doesNotMatchSimilarPrefix`: `com.google.ChromeCanary` is not matched for `com.google.Chrome`. A match means the id is equal, or starts with the browser id followed by `.`.
- [ ] **Step 2:** Run `swift test --filter BrowserAudioProcessesTests`. Expected: FAIL (symbols undefined).
- [ ] **Step 3:** Implement `matching`. Implement `allAudioProcesses` by reading `kAudioHardwarePropertyProcessObjectList`, then `kAudioProcessPropertyPID` and `kAudioProcessPropertyBundleID` for each object. `runningBrowsers` filters `NSWorkspace.shared.runningApplications` against this list: Chrome `com.google.Chrome`, Safari `com.apple.Safari`, Arc `company.thebrowser.Browser`, Edge `com.microsoft.edgemac`, Firefox `org.mozilla.firefox`, Whale `com.naver.Whale`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Implement `ProcessTapCapture`:
  - Create `CATapDescription(stereoMixdownOfProcesses: <matched ids>)` with `muteBehavior = .unmuted` and `isPrivate = true`.
  - Call `AudioHardwareCreateProcessTap`, then create a private aggregate device with `kAudioAggregateDeviceIsPrivateKey: true`, `kAudioAggregateDeviceTapListKey` holding the tap UUID, and `kAudioAggregateDeviceTapAutoStartKey: true`.
  - Read the format from `kAudioTapPropertyFormat`.
  - Use `AudioDeviceCreateIOProcIDWithBlock` to copy each input buffer list into an `AVAudioPCMBuffer` and yield it.
  - `stop()` destroys the IOProc, the aggregate device, then the tap.
  - Re-read the process list on every `start()`, because Chrome spawns its audio helper lazily.
- [ ] **Step 6:** `TapProbe`: `swift run TapProbe com.google.Chrome 10 /tmp/probe.wav` captures 10 s, writes a WAV with `AVAudioFile`, and prints the matched process count and peak level.
- [ ] **Step 7: Manual verification.** Play a YouTube video in Chrome and run the probe. macOS only asks for audio-capture permission for a process whose bundle has `NSAudioCaptureUsageDescription`. If the bare CLI gets silence and no prompt, add a hidden `--probe <seconds> <path>` launch argument to the app and run it from `build/EarningsTranslator.app`. Expected: peak level > 0.01, and `afplay /tmp/probe.wav` plays the video audio. **If this fails after reasonable effort, stop and report to the user before continuing**, because the spec names this as the top risk.
- [ ] **Step 8:** Commit `feat: capture browser audio via Core Audio process tap`.

### Task 2: Quantity model and English extractor

**Files:**
- Create: `Sources/TranslatorCore/Numbers/Quantity.swift`, `Sources/TranslatorCore/Numbers/EnglishQuantityExtractor.swift`
- Test: `Tests/TranslatorCoreTests/EnglishQuantityExtractorTests.swift`

**Interfaces:**
- Produces:
  - `public enum QuantityUnit: Sendable, Hashable { case plain, percent, percentagePoints, basisPoints, quarter, fiscalYear }`
  - `public struct Quantity: Sendable, Hashable, CustomStringConvertible { public let value: Decimal; public let unit: QuantityUnit; public init(_ value: Decimal, _ unit: QuantityUnit) }`. `value` is normalized: currency symbols are dropped, scale words are multiplied out, and two-digit fiscal years become `20xx`.
  - `public enum EnglishQuantityExtractor { public static func extract(_ text: String) -> [Quantity] }` (in order of appearance)

- [ ] **Step 1: Write failing tests** (`#expect(EnglishQuantityExtractor.extract(s) == [...])`):
  - `"Revenue was $94.9 billion, up 6% year over year."` → `[94_900_000_000 plain, 6 percent]`
  - `"EPS of $1.64"` → `[1.64 plain]`
  - `"margin expanded 120 basis points"` and `"120 bps"` → `[120 basisPoints]`
  - `"up 2.5 percentage points"` → `[2.5 percentagePoints]`
  - `"Q3"`, `"third quarter"`, `"the first quarter"` → `[3 quarter]`, `[3 quarter]`, `[1 quarter]` (ordinals first through fourth)
  - `"fiscal 2026"`, `"FY26"`, `"fiscal '26"`, `"fiscal twenty-six"` → `[2026 fiscalYear]`
  - `"1,250 million"` → `[1_250_000_000 plain]`; `"$3.2 trillion"` → `[3_200_000_000_000 plain]`
  - `extractsRangeBothEnds`: `"$1.60 to $1.65"` → `[1.60 plain, 1.65 plain]`
  - `repeatedValuesAreCounted`: `"3% and then 3%"` → two `3 percent`
  - `"down 3%"` → `[3 percent]` (sign words are ignored on purpose)
  - `"in 2025"` → `[2025 plain]`
- [ ] **Step 2:** Run `swift test --filter EnglishQuantityExtractorTests`. Expected: FAIL.
- [ ] **Step 3:** Implement as a single left-to-right pass:
  - First match the quarter and fiscal-year patterns and consume them.
  - Then match `\$?\d[\d,]*(\.\d+)?` followed by an optional `\s*(trillion|billion|million|thousand|%|percent|percentage points?|basis points?|bps?)`.
  - Parse with `Decimal(string:)` after removing commas. Never use `Double`.
  - General number words ("two hundred") are out of scope; the speech recognizer emits digits.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: extract quantities from English text`.

### Task 3: Korean extractor

**Files:**
- Create: `Sources/TranslatorCore/Numbers/KoreanQuantityExtractor.swift`
- Test: `Tests/TranslatorCoreTests/KoreanQuantityExtractorTests.swift`

**Interfaces:**
- Consumes: `Quantity`, `QuantityUnit` (Task 2)
- Produces: `public enum KoreanQuantityExtractor { public static func extract(_ text: String) -> [Quantity] }`

- [ ] **Step 1: Write failing tests:**
  - `"매출은 949억 달러로 전년 대비 6% 증가"` → `[94_900_000_000 plain, 6 percent]`
  - `"1조 2,000억 달러"` → `[1_200_000_000_000 plain]` (adjacent units combine into one quantity)
  - `"3조 2천억"` → `[3_200_000_000_000 plain]`
  - `"12억 5천만 달러"` → `[1_250_000_000 plain]`
  - `"주당순이익(EPS) 1.64달러"` → `[1.64 plain]`
  - `"120bp"`, `"120 베이시스포인트"` → `[120 basisPoints]`
  - `"2.5%p"`, `"2.5%포인트"` → `[2.5 percentagePoints]`
  - `"3분기"` → `[3 quarter]`; `"2026 회계연도"`, `"2026회계연도"` → `[2026 fiscalYear]`
  - `"1.60~1.65달러"` and `"1.60달러에서 1.65달러"` → `[1.60 plain, 1.65 plain]`
  - `"2025년"` → `[2025 plain]`
- [ ] **Step 2:** Run `swift test --filter KoreanQuantityExtractorTests`. Expected: FAIL.
- [ ] **Step 3:** Implement. Tokenize into `number (unit)?` chunks, where the unit is `조`=1e12, `억`=1e8, `만`=1e4 or `천`=1e3. Combine consecutive chunks separated only by spaces:

  ```
  total = 0; group = 0
  for (n, unit) in chunks:
      if unit in {조, 억, 만}: total += (group + n) * scale(unit); group = 0
      elif unit == 천:        group += n * 1000
      else:                   group += n
  result = total + group
  ```

  After the sequence, check these suffixes in order: `%p` or `%포인트` → percentagePoints, `%` → percent, `bp` or `베이시스포인트` → basisPoints, `분기` → quarter, `회계연도` (optional leading space) → fiscalYear. Anything else is plain.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: extract quantities from Korean text`.

### Task 4: Glossary, validator, segment model

**Files:**
- Create: `Sources/TranslatorCore/Glossary/Glossary.swift`, `Sources/TranslatorCore/Validation/TranslationValidator.swift`, `Sources/TranslatorCore/Model/Segment.swift`
- Test: `Tests/TranslatorCoreTests/GlossaryTests.swift`, `Tests/TranslatorCoreTests/TranslationValidatorTests.swift`, `Tests/TranslatorCoreTests/Fixtures/earnings-sentences.json`

**Interfaces:**
- Consumes: both extractors
- Produces:
  - `public struct GlossaryEntry: Codable, Sendable, Hashable { public let english: [String]; public let korean: [String] }`. `korean` lists acceptable renderings; `korean[0]` is the preferred form used in the prompt.
  - `public struct Glossary: Sendable { public let entries: [GlossaryEntry]; public static let standard: Glossary; public static func load(from url: URL) throws -> Glossary; public func save(to url: URL) throws; public func entries(presentIn english: String) -> [GlossaryEntry] }`
  - `public enum ValidationIssue: Sendable, Hashable { case missingQuantity(Quantity), extraQuantity(Quantity), missingTerm(GlossaryEntry), emptyTranslation, untranslatedEnglish }`
  - `public enum TranslationValidator { public static func validate(english: String, korean: String, glossary: Glossary) -> [ValidationIssue] }`
  - `public enum SegmentStatus: Sendable, Equatable { case pending, translating, done, flagged([ValidationIssue]) }`
  - `public struct Segment: Sendable, Identifiable, Equatable { public let id: UUID; public let start: TimeInterval; public let english: String; public var korean: String?; public var status: SegmentStatus }`

- [ ] **Step 1: Write failing tests:**
  - `Glossary.standard` contains at least these entries (english → korean[0]):
    - EPS / earnings per share → 주당순이익
    - guidance / outlook → 가이던스
    - year over year / year-over-year → 전년 대비
    - quarter over quarter / sequentially → 전 분기 대비
    - operating margin → 영업이익률
    - gross margin → 매출총이익률
    - free cash flow → 잉여현금흐름
    - headwind → 역풍
    - tailwind → 순풍
    - beat → 상회
    - miss → 하회
    - consensus → 컨센서스
    - buyback / share repurchase → 자사주 매입
    - dividend → 배당
    - revenue → 매출
    - net income → 순이익
    - operating income → 영업이익
    - capex / capital expenditures → 설비투자
    - low-single digits → 한 자릿수 초반
    - mid-single digits → 한 자릿수 중반
    - high-single digits → 한 자릿수 후반
    - double digits → 두 자릿수
  - `entries(presentIn:)` matches case-insensitively, on word boundaries, with an optional trailing `s`/`es`: `"Headwinds"` matches headwind, but `"beaten path"` does not match beat.
  - The Glossary round-trips through `save(to:)` and `load(from:)`.
  - Validator:
    - matching numbers and terms → `[]`
    - `"$94.9 billion"` vs `"94억 9천만 달러"` → `[.missingQuantity(94_900_000_000 plain), .extraQuantity(9_490_000_000 plain)]`
    - a Korean number the English never said → `.extraQuantity`
    - `"guidance"` with no 가이던스 → `.missingTerm`
    - `emptyTranslationIsFlagged`: `""` or whitespace only → `[.emptyTranslation]`
    - ≥ 4 consecutive ASCII words in the translation (glossary acronyms such as EPS don't count) → `.untranslatedEnglish`
  - A fixture test loads `earnings-sentences.json` (≥ 15 `{ "en", "ko", "expectedIssueCount" }` objects covering every `QuantityUnit`) and checks each count.
- [ ] **Step 2:** Run `swift test --filter "GlossaryTests|TranslationValidatorTests"`. Expected: FAIL.
- [ ] **Step 3:** Implement. Compare quantities as multisets (counted dictionaries): English minus Korean → missing, Korean minus English → extra.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: validate translated numbers and glossary terms`.

### Task 5: Prompt builder and Ollama client

**Files:**
- Create: `Sources/TranslatorCore/Translation/PromptBuilder.swift`, `Sources/TranslatorCore/Translation/OllamaClient.swift`
- Test: `Tests/TranslatorCoreTests/PromptBuilderTests.swift`, `Tests/TranslatorCoreTests/OllamaClientTests.swift` (with a `URLProtocol` stub)

**Interfaces:**
- Consumes: `Glossary`, `ValidationIssue`
- Produces:
  - `public struct TranslationItem: Sendable, Equatable { public let id: Int; public let english: String }`
  - `public struct ContextPair: Sendable, Equatable { public let english: String; public let korean: String }`
  - `public protocol TranslationBackend: Sendable { func translate(_ items: [TranslationItem], context: [ContextPair], hints: [ValidationIssue]) async throws -> [Int: String]; func health() async -> BackendHealth }`
  - `public enum BackendHealth: Sendable, Equatable { case ok, unreachable, modelMissing(String) }`
  - `public enum BackendError: Error, Equatable { case unreachable, http(Int), malformedResponse }`
  - `public struct OllamaClient: TranslationBackend { public init(baseURL: URL = URL(string: "http://localhost:11434")!, model: String, glossary: Glossary, session: URLSession = .shared) }`
  - `public enum PromptBuilder { public static func systemPrompt(glossary: Glossary) -> String; public static func userMessage(items: [TranslationItem], context: [ContextPair], hints: [ValidationIssue]) -> String; public static var responseSchema: [String: Any] { get } }`

- [ ] **Step 1: Write failing tests:**
  - The system prompt contains each rule:
    - exact unit conversion, with the example `$94.9 billion → 949억 달러`
    - keep %, bp and %p
    - `Q3 → 3분기`, `FY2026 → 2026 회계연도`
    - never add numbers that were not said
    - translate everything into Korean, with no commentary
    - use the glossary renderings
  - The system prompt contains every glossary `english → korean[0]` line.
  - `userMessage` lists the context pairs first under `이전 문맥`, then the items as `[id] text`. With hints, it adds one line per issue, e.g. `원문의 94900000000 값이 번역에 없습니다`.
  - Request: POST `/api/chat`, body has `model`, `stream:false`, `keep_alive:"2h"`, `options.temperature:0`, `think:false`, and `format` equal to `responseSchema`.
  - Decodes `{"message":{"content":"{\"translations\":[{\"id\":1,\"ko\":\"...\"}]}"}}` into `[1: "..."]`.
  - Non-JSON content → `.malformedResponse`. Connection refused → `.unreachable`. HTTP 404 → `.http(404)`.
  - `health()`: GET `/api/tags` → `.ok` when `models[].name` contains the model, `.modelMissing(model)` otherwise, `.unreachable` on connection error.
- [ ] **Step 2:** Run `swift test --filter "PromptBuilderTests|OllamaClientTests"`. Expected: FAIL.
- [ ] **Step 3:** Implement. `responseSchema` = `{"type":"object","properties":{"translations":{"type":"array","items":{"type":"object","properties":{"id":{"type":"integer"},"ko":{"type":"string"}},"required":["id","ko"]}}},"required":["translations"]}`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: Ollama translation client with structured output`.

### Task 6: Model bench — choose the default model

**Files:**
- Create: `Sources/TranslateBench/main.swift`, `docs/model-bench.md`

**Interfaces:**
- Consumes: `OllamaClient`, `TranslationValidator`, `Glossary.standard`, the Task 4 fixture file (passed by path)

- [ ] **Step 1:** Run `ollama pull gemma4:12b` and `ollama pull gemma4:26b`. Expected: both are listed in `ollama list`.
- [ ] **Step 2:** Implement `swift run TranslateBench <model> <fixtures.json>`. For each model it:
  - warms up once
  - translates every fixture English sentence singly, then again in batches of 4
  - prints median and p90 latency for single and batch calls, the count of sentences with any `ValidationIssue`, and each flagged sentence with its translation
- [ ] **Step 3:** Run the bench for both models. If Ollama rejects `think:false` for gemma4, remove the field from `OllamaClient` (and its test) and note this in `docs/model-bench.md`.
- [ ] **Step 4:** Record the results table in `docs/model-bench.md`. Choose the default: fewer flagged sentences wins, and a tie goes to the faster model. If the winner's median single latency is over 4 s, choose `gemma4:12b` and note why. Task 10 uses the recorded default. **Show the user the table before continuing.**
- [ ] **Step 5:** Commit `chore: benchmark gemma4 models for translation`.

### Task 7: Translation queue

**Files:**
- Create: `Sources/TranslatorCore/Translation/TranslationQueue.swift`
- Test: `Tests/TranslatorCoreTests/TranslationQueueTests.swift` (scripted fake `TranslationBackend`)

**Interfaces:**
- Consumes: `TranslationBackend`, `TranslationValidator`, `Glossary`, `Segment`, `SegmentStatus`
- Produces:
  - `public struct SegmentUpdate: Sendable, Equatable { public let id: UUID; public let korean: String?; public let status: SegmentStatus }`
  - `public enum QueueHealth: Sendable, Equatable { case ok, delayed(backlog: Int), offline }`
  - `public actor TranslationQueue { public init(backend: any TranslationBackend, glossary: Glossary, maxBatch: Int = 6, delayedThreshold: Int = 4, contextSize: Int = 3, retryInterval: Duration = .seconds(3)); public func enqueue(_ segment: Segment); public nonisolated var updates: AsyncStream<SegmentUpdate> { get }; public nonisolated var health: AsyncStream<QueueHealth> { get }; public func finish() async }`. `finish()` returns once the queue is empty or the backend is offline.

- [ ] **Step 1: Write failing tests** (pass `retryInterval: .milliseconds(10)`):
  - `singleSegmentIsTranslated`: emits `.translating`, then `.done` with the Korean text.
  - `backlogIsBatched`: enqueue 5 while the fake blocks the first call, then release it. The second call gets 4 items in enqueue order.
  - `failedValidationRetriesOnceWithHints`: the first reply has a wrong number. The retry is a single-item call whose `hints` contains `.missingQuantity`. A correct retry gives `.done`; a second wrong reply gives `.flagged`.
  - `emptyTranslationIsFlagged`
  - `batchReplyWithWrongCountFallsBackToSingles`: a missing id or malformed reply leads to each item being retried singly, and none is lost.
  - `offlineKeepsOrderAndResumes`: the fake throws `.unreachable` twice. Health goes to `.offline`, then `.ok`, and all segments end `.done` in enqueue order.
  - `delayedHealthReported`: a backlog of ≥ 4 emits `.delayed(backlog:)`.
  - `contextUsesLastThreeDonePairs`
  - `queueIdlesAndResumes`: after the queue drains, a later segment is still processed.
- [ ] **Step 2:** Run `swift test --filter TranslationQueueTests`. Expected: FAIL.
- [ ] **Step 3:** Implement with one worker task that loops:
  1. Wait for pending work.
  2. Take up to `maxBatch` items in order.
  3. Call the backend.
  4. Validate each result.
  5. Retry failures singly with hints.
  6. Emit the updates.

  On `.unreachable`, emit `.offline`, sleep `retryInterval`, and retry the same batch.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: translation queue with batching, retry and offline recovery`.

### Task 8: Sentence splitting and live transcription

**Files:**
- Create: `Sources/TranslatorCore/Transcript/SentenceSplitter.swift`, `Sources/TranslatorSystem/Speech/LiveTranscriber.swift`
- Test: `Tests/TranslatorCoreTests/SentenceSplitterTests.swift`, `Tests/TranslatorSystemTests/LiveTranscriberIntegrationTests.swift`

**Interfaces:**
- Produces:
  - `public enum SentenceSplitter { public static func split(_ text: String, maxWords: Int = 40) -> [String] }`
  - `public enum TranscriptEvent: Sendable, Equatable { case volatile(String); case final(text: String, start: TimeInterval); case assetDownload(progress: Double) }`
  - `public final class LiveTranscriber: @unchecked Sendable { public init(locale: Locale = Locale(identifier: "en-US")); public func prepare() -> AsyncThrowingStream<Double, Error>; public func start(audio: AsyncStream<AVAudioPCMBuffer>, naturalFormat: AVAudioFormat?) -> AsyncStream<TranscriptEvent>; public func stop() async }`. `prepare` yields asset-download progress from 0 to 1 and finishes when ready.
  - `public enum TranscriberError: Error { case localeUnsupported, assetsUnavailable }`

- [ ] **Step 1: Write failing tests:**
  - Splitter:
    - ≤ 40 words → one element, unchanged.
    - A 90-word text splits at `.?!` first, then `;`, then `,`, so every chunk has ≤ 40 words where such a boundary exists.
    - A run with no boundary is hard-split at 40 words.
    - All words are preserved in order (joined output == whitespace-normalized input).
  - Integration test, enabled only when `RUN_SPEECH_TESTS=1`: generate `/tmp/et-say.aiff` with `say -o /tmp/et-say.aiff "Revenue was 94.9 billion dollars, up 6 percent year over year."`, feed the file's buffers as the stream, and expect a `.final` whose text contains `94.9` and `6`.
- [ ] **Step 2:** Run `swift test --filter SentenceSplitterTests`. Expected: FAIL.
- [ ] **Step 3:** Implement the splitter. Run its tests. Expected: PASS.
- [ ] **Step 4:** Implement `LiveTranscriber`:
  - Create `SpeechTranscriber(locale:, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])`.
  - `prepare()` checks `SpeechTranscriber.supportedLocales` and installs assets via `AssetInventory.assetInstallationRequest(supporting:)`, yielding its progress.
  - Convert input buffers to `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:considering:)` with `AVAudioConverter`, wrap them as `AnalyzerInput`, and feed `analyzer.start(inputSequence:)`.
  - Map `results`: a non-final result → `.volatile`; a final result → `.final` with `start = audioTimeRange.start.seconds`.
  - `stop()` calls `finalizeAndFinishThroughEndOfInput()`.
- [ ] **Step 5:** Run `RUN_SPEECH_TESTS=1 swift test --filter LiveTranscriberIntegrationTests`. Expected: PASS. The first run may download the en-US assets.
- [ ] **Step 6:** Commit `feat: on-device live transcription and sentence splitting`.

### Task 9: Markdown export and autosave

**Files:**
- Create: `Sources/TranslatorCore/Export/MarkdownExporter.swift`, `Sources/TranslatorCore/Export/TranscriptAutosaver.swift`
- Test: `Tests/TranslatorCoreTests/MarkdownExporterTests.swift`, `Tests/TranslatorCoreTests/TranscriptAutosaverTests.swift`

**Interfaces:**
- Consumes: `Segment`, `SegmentStatus`
- Produces:
  - `public enum MarkdownExporter { public static func render(segments: [Segment], sessionStart: Date) -> String; public static func fileName(for sessionStart: Date) -> String }`
  - `public actor TranscriptAutosaver { public init(folder: URL, sessionStart: Date, interval: Duration = .seconds(5)); public func update(_ segments: [Segment]); public func flush() throws; public func setFolder(_ url: URL); public nonisolated var errors: AsyncStream<any Error> { get }; public var fileURL: URL { get } }`. A background timer calls `flush()` every `interval` while dirty, and reports failures on `errors`.

- [ ] **Step 1: Write failing tests:**
  - `render` output for a session starting at 2026-11-04 18:30 local, with three segments at 5 s (done), 12 s (flagged) and 20 s (pending), is exactly:

    ```
    # 실적 발표 번역 — 2026-11-04 18:30

    **[00:00:05]** Revenue was $94.9 billion.
    > 매출은 949억 달러였습니다.

    **[00:00:12]** Guidance was raised.
    > ⚠ 가이던스를 올렸습니다.

    **[00:00:20]** Thank you.
    > (번역 대기 중)
    ```

  - `fileName(for:)` gives `"2026-11-04_1830.md"`.
  - After `update` + `flush`, the autosaver writes the file atomically. A second `flush` with no change does not touch the file (its modification date is unchanged).
  - `autosaveFailureKeepsDirtyAndReportsError`: with the folder deleted, `flush` throws. After `setFolder(newDir)`, `flush` writes the full content.
- [ ] **Step 2:** Run `swift test --filter "MarkdownExporterTests|TranscriptAutosaverTests"`. Expected: FAIL.
- [ ] **Step 3:** Implement. `.pending` and `.translating` render as `(번역 대기 중)`; `.flagged` prefixes `⚠ `.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: markdown transcript export with autosave`.

### Task 10: Session controller and UI

**Files:**
- Create: `Sources/EarningsTranslator/SessionController.swift`, `Settings.swift`, `Views/TranscriptView.swift`, `Views/SegmentRow.swift`, `Views/ToolbarView.swift`, `Views/StatusBanner.swift`
- Modify: `Sources/EarningsTranslator/EarningsTranslatorApp.swift`

**Interfaces:**
- Consumes: every Produces block above.
- Produces:
  - `@MainActor @Observable final class SessionController`:
    - `var segments: [Segment]`
    - `var liveEnglish: String?`
    - `var isRunning: Bool`
    - `var browsers: [Browser]`
    - `var selectedBrowser: Browser?`
    - `var banner: Banner?`
    - `func start() async`, `func stop() async`, `func saveNow() async`
  - `enum Banner: Equatable { case ollamaUnreachable, modelMissing(String), translationDelayed(Int), permissionDenied, speechAssetDownloading(Double), saveFailed(String), browserQuit }`
  - `Settings`: UserDefaults keys `modelTag` (default from `docs/model-bench.md`), `saveFolderPath`, `pinOnTop`.

- [ ] **Step 1:** Implement `SessionController.start()`:
  - Check backend `health()`. If it is not `.ok`, set the banner but still start; the queue recovers by itself.
  - If no save folder is set, show an `NSOpenPanel` folder picker once and store the choice.
  - Load the glossary from `~/Library/Application Support/EarningsTranslator/glossary.json`. If the file is missing, write `Glossary.standard` there first.
  - Run `LiveTranscriber.prepare()`, mapping progress to `.speechAssetDownloading`.
  - Start `ProcessTapCapture`, then `LiveTranscriber.start`.
  - For each `.final`: run `SentenceSplitter`, append a `.pending` `Segment` with `start` offset from the session start, `enqueue` it, and call `autosaver.update`.
  - `.volatile` sets `liveEnglish`.
  - Queue `updates` patch segments and call `autosaver.update`. Queue `health` maps to the banner. Autosaver `errors` map to `.saveFailed`.
  - On `NSWorkspace.didTerminateApplicationNotification` for the selected browser: `stop()`, then banner `.browserQuit`.
  - `CaptureError.permissionDenied`, or zero peak level for the first 5 s while Chrome is playing, sets `.permissionDenied`. That banner points to `시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음`.
- [ ] **Step 2:** Implement `stop()`: stop capture, then `transcriber.stop()`, `queue.finish()`, and `autosaver.flush()`.
- [ ] **Step 3:** Views (spec design B):
  - `SegmentRow`: English in `.callout` with `.secondary` color, Korean in `.title3`. Flagged rows show `⚠` with `.help(<tooltip copy from Global Constraints>)`.
  - The live row (`liveEnglish`) gets a `Color.yellow.opacity(0.18)` background.
  - `TranscriptView` auto-scrolls. When the user scrolls away from the bottom (`onScrollGeometryChange`), auto-scroll pauses and a `최신으로` button appears.
  - `ToolbarView`:
    - browser `Picker` (Chrome preselected when running)
    - `시작`/`정지` button
    - `저장` button
    - pin toggle (`NSWindow.level = .floating` when on)
    - model picker
  - `StatusBanner` renders each `Banner` in Korean. The `modelMissing(m)` banner includes `ollama pull \(m)`.
- [ ] **Step 4:** Run `swift build && scripts/build-app.sh debug && open build/EarningsTranslator.app`. Expected: the toolbar shows. With Ollama stopped, choosing Chrome and pressing 시작 shows the Ollama banner without crashing.
- [ ] **Step 5:** Commit `feat: transcript window and session orchestration`.

### Task 11: End-to-end verification and README

**Files:**
- Create: `README.md`

- [ ] **Step 1:** Run `swift test`, then `RUN_SPEECH_TESTS=1 swift test`. Expected: all pass. Quote each summary line in the task report.
- [ ] **Step 2: Manual end-to-end check.** Start `ollama serve` with the default model pulled. Play a real earnings-call replay in Chrome (an IR webcast or a YouTube upload) for ≥ 10 minutes. Expected:
  - English rows appear and Korean fills in within a few seconds.
  - `delayed` never persists for more than about 30 s.
  - The ⚠ tooltip shows on hover.
  - Scrolling up pauses auto-scroll, and `최신으로` returns to the bottom.
  - The `.md` file updates while running.
  - Pausing the video for 2 minutes and resuming continues transcription (Review Focus 2).
  - Quitting Chrome stops the session and saves.
- [ ] **Step 3:** Record the ⚠ count and any wrong English numbers you noticed in the report, so the user can decide whether the deferred recognition check is needed.
- [ ] **Step 4:** Write `README.md` in Korean, covering:
  - requirements: macOS 26+, Ollama, `ollama pull <default model>`
  - build: `scripts/build-app.sh release`
  - first-run permissions
  - editing `glossary.json`
  - what ⚠ means (the tooltip copy)
- [ ] **Step 5:** Commit `docs: README and end-to-end verification notes`.
