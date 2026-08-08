# Plynn Roadmap

Fully-local dictation for macOS. Everything on-device, always.

## Shipped

- **Phase 0–1 — Core dictation:** hold-fn dictation with streaming partials
  (Parakeet via FluidAudio on the Neural Engine), VAD silence gate, floating
  Liquid Glass indicator, secure-field guard, Apple SpeechTranscriber as the
  zero-download onboarding engine, paste with press-enter support.
- **Phase 2 — Formatting:** instant rules pass (spoken punctuation, new line,
  press enter) + AI polish (fillers, self-corrections, lists, per-app tone) via
  Apple Intelligence on-device, with a latency gate so clean short dictations
  paste instantly.
- **Phase 3 — Personalization:** custom dictionary with aliases + CSV import,
  spoken snippets, dictation history + stats (local SQLite), auto-learning
  from your corrections, Wispr Flow data import.

## Next

- **Phase 4 — Command mode & release polish**
  - Selection transforms: select text, hold fn, say "make this shorter" —
    with a before/after diff preview.
  - Generation at cursor ("write a polite decline").
  - Onboarding practice exercises; URL scheme (`plynn://`).
  - Sparkle auto-updates, notarized DMG, GitHub release pipeline.

- **Phase 5 — Power features**
  - **Custom polish models — swap in Settings.** Pick the model that does AI
    polish: Apple Intelligence (default), bundled Qwen3-4B, or any MLX-community
    model ID pasted into Settings (downloaded and run locally via MLX). The
    engine abstraction (`PolishPrompt` + per-engine formatters) already
    supports this; the work is Settings UI + download management.
  - Max-accuracy re-transcription pass (Whisper large-v3-turbo) for noisy audio.
  - ASR-level dictionary boosting (CTC keyword spotting — needs FluidAudio's
    sliding-window manager).
  - Scratchpad window; meeting mode with speaker diarization.
  - Multilingual (Parakeet v3 / Whisper).

## Explicitly never

- Cloud transcription, telemetry, accounts. Audio and text never leave the Mac.
