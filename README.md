# EarningsTranslator

브라우저에서 듣는 미국 기업 실적 발표(earnings call)를 실시간으로 한국어 자막으로 보여주는 맥 앱입니다.

- 고른 브라우저(기본: Chrome)의 **소리만** 가져옵니다. 화면은 캡처하지 않습니다.
- 영어는 맥에 내장된 온디바이스 음성 인식으로 받아 적고, 로컬 **Gemma 4**(Ollama)가 한국어로 번역합니다.
- 모든 처리가 맥 안에서 이뤄집니다. 오디오와 대본은 인터넷으로 나가지 않습니다.
- 대본은 마크다운 파일로 자동 저장됩니다.

## 준비물

- macOS 26 이상 (Apple Silicon)
- [Ollama](https://ollama.com) **0.40 이상**. 0.15 같은 예전 버전은 Gemma 4를 내려받지 못합니다.
  ```bash
  brew upgrade ollama && brew services restart ollama
  ollama pull gemma4:12b
  ```
- Xcode는 없어도 됩니다. Command Line Tools(Swift 6.2 이상)만 있으면 빌드할 수 있습니다.

## 빌드와 실행

```bash
scripts/build-app.sh release
open build/EarningsTranslator.app
```

`build/EarningsTranslator.app`을 응용 프로그램 폴더로 옮겨 써도 됩니다.

## 처음 실행할 때

1. 실적 발표 영상을 Chrome에서 먼저 재생합니다.
2. 앱에서 브라우저(Chrome)를 고르고 **시작**을 누릅니다.
3. 아래 권한을 허용합니다.
   - **음성 인식**: 영어를 받아 적는 데 필요합니다.
   - **시스템 오디오 녹음**: 브라우저 소리를 듣는 데 필요합니다.
4. 대본을 저장할 폴더를 한 번 고릅니다.
5. 처음 한 번은 영어 음성 모델을 내려받습니다. 진행률이 화면 위에 표시됩니다.

권한을 거부했다면 **시스템 설정 > 개인정보 보호 및 보안**에서 *음성 인식*과 *화면 및 시스템 오디오 녹음* 항목을 확인하세요.

## 화면 보는 법

- 문장마다 위에 영어 원문(작은 글씨), 아래에 한국어 번역(큰 글씨)이 표시됩니다.
- 노란 줄은 지금 말하고 있는 문장입니다. 번역은 보통 1~3초 뒤에 채워집니다.
- 위로 스크롤하면 자동 따라가기가 멈추고 **최신으로** 버튼이 나타납니다. 맨 아래로 내리면 다시 따라갑니다.
- 📌 버튼을 켜면 창이 다른 창 위에 항상 떠 있고, 모든 데스크톱과 전체 화면 영상 위에도 따라다닙니다. 끄면 일반 창이 되어 Mission Control에서 원하는 데스크톱으로 옮길 수 있습니다.
- 모델은 상단 메뉴에서 바꿀 수 있습니다(`gemma4:e4b`, `gemma4:12b`, `gemma4:26b`). 기본값은 `gemma4:12b`입니다. 이유는 [docs/model-bench.md](docs/model-bench.md)에 있습니다.

### ⚠ 표시의 뜻

> 번역의 숫자나 용어가 영어 원문과 다를 수 있습니다. 영어 받아쓰기 자체의 오류는 검사하지 않습니다.

앱은 번역할 때마다 영어 원문과 한국어 번역의 숫자(억/조 단위, %, bp, %p, 분기, 회계연도)와 실적 용어를 비교합니다. 다르면 한 번 다시 번역해 보고, 그래도 다르면 ⚠를 붙입니다. 이때는 바로 위의 영어 원문을 확인하세요.

## 저장 파일

- 고른 폴더에 `YYYY-MM-DD_HHmm.md` 이름으로 저장됩니다(세션 시작 시각 기준).
- 녹음 중에는 5초마다 자동 저장되고, 정지하면 마지막으로 한 번 더 저장합니다.
- 형식:
  ```markdown
  **[00:12:34]** Revenue was $94.9 billion, up 6% year over year.
  > 매출은 949억 달러로 전년 대비 6% 증가했습니다.
  ```

## 용어집 고치기

번역에 쓰는 실적 용어집은 `~/Library/Application Support/EarningsTranslator/glossary.json`에 있습니다. 처음 실행할 때 기본값으로 만들어집니다.

```json
{ "english": ["guidance"], "korean": ["가이던스"] }
```

- `english`: 이 단어가 원문에 나오면 항목이 적용됩니다. 복수형(s/es)도 자동으로 잡습니다.
- `korean`: 인정하는 번역어 목록입니다. 첫 번째가 번역할 때 쓰도록 요청하는 표현입니다.

고친 내용은 다음 세션을 시작할 때 반영됩니다.

## 문제 해결

| 화면 안내 | 할 일 |
|---|---|
| Ollama에 연결할 수 없습니다 | 터미널에서 `brew services start ollama`(또는 `ollama serve`)를 실행하세요. 받아쓰기는 계속되고, 연결되면 밀린 문장부터 번역합니다. |
| 번역 모델이 없습니다 | 안내에 나온 `ollama pull …` 명령을 실행하세요. |
| 브라우저 소리가 들리지 않습니다 | 영상이 재생 중인지 확인하고, *화면 및 시스템 오디오 녹음* 권한을 확인하세요. |
| 번역 지연 중 | 문장이 밀려 있다는 뜻입니다. 여러 문장을 묶어서 따라잡으니 잠시 기다리세요. |

## 개발

```bash
scripts/test.sh            # 단위 테스트 (swift test + Xcode 없는 환경용 플러그인 경로)
scripts/speech-check.sh    # 앱 번들 안에서 음성 인식 확인
swift run TapProbe com.google.Chrome 5 /tmp/probe.wav    # 브라우저 소리 캡처 확인
swift run TranslateBench gemma4:12b Tests/TranslatorCoreTests/Fixtures/earnings-sentences.json
```

- 설계 문서: [docs/superpowers/specs/2026-11-04-earnings-call-translator-design.md](docs/superpowers/specs/2026-11-04-earnings-call-translator-design.md)
- `swift test`를 바로 쓰지 말고 `scripts/test.sh`를 쓰세요. Command Line Tools만 있는 환경에서는 증분 빌드가 swift-testing 매크로 플러그인 경로를 빠뜨릴 때가 있습니다.
- SwiftUI의 `@State`는 쓰지 않습니다. 이 SDK에서는 매크로인데, 그 플러그인이 Xcode에만 들어 있습니다.
