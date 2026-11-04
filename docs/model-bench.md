# Gemma 4 model bench

Date: 2026-11-04 · Machine: Apple M4, 24 GB · Ollama 0.40.14
Command: `swift run TranslateBench <model> Tests/TranslatorCoreTests/Fixtures/earnings-sentences.json`
(15 distinct earnings-call sentences; "flagged" = any number/term validation issue)

| Model | Single median | Single p90 | Batch of 4 median | Batch p90 | Flagged (single / batch) | Resident size |
|---|---|---|---|---|---|---|
| gemma4:12b | 1.86 s | 2.34 s | 7.28 s | 8.15 s | 0/15 / 0/15 | ~8 GB |
| gemma4:26b (MoE) | 1.13 s | 1.49 s | 3.70 s | 4.21 s | 0/15 / 0/15 | 21 GB (`ollama ps`) |

## Default: `gemma4:12b`

The plan's rule (fewer flags wins; tie → faster) would pick `gemma4:26b`. It was
overridden for memory: with 26b loaded the system had 10% free memory and
15.9 of 16 GB swap in use, on a machine that is also playing the call in Chrome
and running speech recognition. The spec chose 12b for that headroom. Both
models were equally accurate, and 12b's ~2 s per sentence is within the
"a few seconds late is fine" budget. 26b stays selectable in the app.

## Notes

- gemma4 on Ollama 0.40.14 rejects any `format` (HTTP 501 "structured output is
  unavailable"), so the client asks for JSON in the prompt and extracts it.
- `think: false` is accepted.
- Ollama 0.15.4 could not pull gemma4 at all (HTTP 412); upgrade to ≥ 0.40.
