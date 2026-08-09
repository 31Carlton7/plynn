# Plynn Roadmap

Fully local dictation for macOS. Everything on device, always.

## Shipped

- **Phases 0 to 1, core dictation:** hold fn dictation with streaming partials
  (Parakeet via FluidAudio on the Neural Engine), a VAD silence gate, the
  floating Liquid Glass indicator, secure field protection, Apple's
  SpeechTranscriber as the zero download onboarding engine, and paste with
  press enter support.
- **Phase 2, formatting:** an instant rules pass (spoken punctuation, new
  line, press enter) plus AI polish (fillers, self corrections, lists, per
  app tone) running on device. A latency gate keeps clean short dictations
  pasting instantly.
- **Phase 3, personalization:** a custom dictionary with aliases and CSV
  import, spoken snippets, dictation history and stats in local SQLite,
  automatic learning from your corrections, and Wispr Flow data import.

## Next

- **Phase 4, command mode and release polish**
  - Selection transforms with a before and after diff preview.
  - Generation at the cursor ("write a polite decline").
  - Onboarding practice exercises and the `plynn://` URL scheme.
  - Sparkle auto updates, notarized DMG, GitHub release pipeline.

- **Phase 5, power features**
  - **Custom polish models you can swap in Settings.** Pick the model that
    does AI polish: Apple Intelligence (the default), the bundled Qwen3 4B,
    or any MLX community model ID pasted into Settings and run locally. The
    engine abstraction already supports this; the remaining work is the
    Settings UI and download management.
  - A max accuracy re transcription pass (Whisper large v3 turbo) for noisy
    audio.
  - Dictionary boosting inside the recognizer itself (CTC keyword spotting,
    which needs FluidAudio's sliding window manager).
  - A scratchpad window, and meeting mode with speaker diarization.
  - Multilingual support (Parakeet v3 and Whisper).

## Never

- Cloud transcription, telemetry, accounts. Audio and text stay on the Mac.
