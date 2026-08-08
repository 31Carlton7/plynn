# Plynn — A Fully-Local Wispr Flow for macOS

*Plan v1.1 — 2026-08-08. Decisions locked: name **Plynn**; **open source**; **macOS 26+ only**; **English-first** at launch.*

**Thesis:** Wispr Flow's product layer is excellent, but it is cloud-only, Electron (~800 MB RAM, ~8% idle CPU), $144/yr, and has a documented privacy-trust deficit (screenshot scandal, audit scandal, Privacy Mode off by default). Meanwhile, local ASR on Apple Silicon now *beats* their cloud pipeline on latency and matches it on clean-audio accuracy — and no local app has shipped the two things that make Wispr feel magical: **streaming text as you speak** and **an AI formatting layer**. Every local competitor (Superwhisper, VoiceInk, MacWhisper, Handy) is record → stop → batch → paste with little or no formatting intelligence. That gap is the product.

**Target hardware:** Apple Silicon, macOS 26 (Tahoe)+ initially. Dev machine: M4 Pro / 24 GB — comfortably fits streaming ASR + a 4B-class LLM simultaneously.

---

## 1. Where we beat Wispr Flow (the "better" checklist)

| Dimension | Wispr Flow | Plynn target |
|---|---|---|
| Latency | <700 ms p99 claimed, 1–2 s felt (cloud round-trip) | **~0.3–0.5 s finals** (Parakeet: 30 s of audio ≈ 0.3 s on M4 Pro); live partials while speaking |
| Streaming display | None — text appears after release | **Live words-as-you-speak** in the indicator (nobody local or cloud does this well) |
| Privacy | Cloud-only; audio → Baseten, text → OpenAI/Anthropic/etc. | **Nothing ever leaves the machine.** Provable (Little Snitch clean) |
| Footprint | Electron, ~800 MB RAM, ~8% idle CPU | Native Swift; target < 100 MB idle, models mmap'd on demand (~0.6 GB int8 ASR + ~2.3 GB LLM when loaded) |
| Offline | Dead on planes / bad Wi-Fi | Fully functional |
| Custom vocabulary | Prompt-level dictionary | **Decoder-level CTC keyword boosting** (FluidAudio: 99.3% dictionary recall) — architecturally better |
| AI-edit trust | History of over-aggressive cleanup complaints | Cleanup levels + **always-visible diff** + one-tap revert to verbatim |
| Reliability seams | Secure-input breakage, paste failures | First-class secure-input handling, paste read-receipts, short-utterance correctness (top competitor bug) |
| Pricing | $12–15/mo subscription | Lifetime purchase possible — zero marginal cost |

Wispr's remaining genuine edges: noise robustness of a huge cloud model, 100+ languages, cross-platform, team features. We concede teams/cross-platform initially; we counter noise/languages with a Whisper large-v3-turbo final-pass option (~100 languages, best accent coverage).

---

## 2. Approaches considered

**A. Native Swift/SwiftUI + FluidAudio (CoreML/ANE) — RECOMMENDED.**
Best Mac polish, ANE-resident inference (low power, doesn't fight GPU), first-class access to every macOS API we need (CGEventTap, AX, NSPanel, SpeechTranscriber, Foundation Models). FluidAudio (Apache-2.0, Swift) already ships Parakeet v3/Unified, Nemotron streaming, Qwen3, Silero VAD, and keyword boosting. This is the stack VoiceInk half-uses; we use it fully plus streaming.

**B. Rust/Tauri (extend Handy, MIT).**
Cross-platform future, great plumbing reference (best-in-class paste and secure-input code). But: web-view UI (the Electron-adjacent feel we're trying to beat), no ANE story (CPU/GGML), weaker access to SpeechTranscriber/Foundation Models/AX. Wrong tool for "quality better than Wispr" on Mac.

**C. Fork VoiceInk (GPL-3).**
Fastest start, but GPL forces our license, its architecture is batch-only (streaming is a rewrite anyway), context is screenshot+OCR (we want AX), and it carries known short-utterance race bugs. Read it, don't fork it.

**Decision: A.** Steal patterns liberally from Handy (MIT — paste read-receipt, secure-input taxonomy) and learn from VoiceInk's code (GPL — reference only, no copying).

---

## 3. Architecture

Un-sandboxed (required for AX/event taps ⇒ no Mac App Store; Developer ID + notarized DMG + Sparkle 2 updates). Menu-bar app (`LSUIElement`, `.accessory` policy). Heavy inference in an **XPC service** so a model crash never kills the app.

```
┌─ Main app (menu bar + settings + onboarding) ─────────────────┐
│  HotkeyMonitor ── AudioEngine ── SessionController            │
│       │               │               │                       │
│  IndicatorPanel (NSPanel, non-activating, live partials)      │
│       │                               │                       │
│  ContextService (AX) ─────────── TextInserter (pasteboard)    │
│  DictionaryStore / SnippetStore / HistoryStore (SQLite/GRDB)  │
└───────────────┬───────────────────────────────────────────────┘
                │ XPC
┌─ InferenceService ────────────────────────────────────────────┐
│  VAD (Silero, FluidAudio)                                     │
│  ASREngine protocol:                                          │
│    • Parakeet TDT Unified (FluidAudio, ANE) — default         │
│    • Nemotron Streaming 0.6B (FluidAudio) — true partials     │
│    • Whisper large-v3-turbo (WhisperKit) — accuracy/languages │
│    • Apple SpeechTranscriber — zero-download onboarding mode  │
│  Formatter:                                                   │
│    • Rules pass (instant, deterministic)                      │
│    • LLM pass — Qwen3-4B-Instruct 4-bit via MLX (GPU)         │
│      fallback: Apple Foundation Models (~3B, ANE, free)       │
└───────────────────────────────────────────────────────────────┘
```

**Key engine decisions**

- **Default ASR: Parakeet TDT (Unified EN / v3 multilingual) via FluidAudio.** 2.2–2.6% WER, 123x RT batch / 29x RT streaming on M4 Pro, native punctuation+caps, word timestamps, int8 ≈ 0.6 GB, and **CTC keyword boosting** for the dictionary. Streaming partials via chunked decode with context carry; optionally swap in Nemotron Streaming (cache-aware, 560 ms chunks, 2.7% WER) for smoother live text.
- **Accuracy/multilingual escape hatch:** on release, optionally re-transcribe the full utterance with Whisper large-v3-turbo (WhisperKit, ~100 languages, best accents/noise) or Qwen3-ASR 1.7B MLX (current on-device WER leader, 1.32%). User-selectable "fast" vs "max accuracy" per-app.
- **ANE contention rule:** ASR lives on the ANE (FluidAudio), the formatting LLM lives on the GPU (MLX). Never both on ANE — Foundation Models (ANE) is only used when ASR is idle.
- **Audio:** raw AUHAL unit bound to an explicit device (doesn't hijack system default), native rate → 16 kHz mono, ring buffer, RMS levels computed lock-free on the RT thread for the waveform, mid-recording device switching (AirPods), no voice processing (raw audio transcribes better). Media auto-pause via MediaRemote during dictation. Start IO only while hotkey held (no permanent orange dot).

**The formatting layer (the moat)**

Two tiers so the common path never waits on an LLM:

1. **Rules pass (0 ms):** spoken punctuation commands ("period", "new line", "press enter"), snippet trigger expansion, dictionary replacements, casing merge with surrounding field text (mid-sentence lowercase, drop trailing period in chat apps), number/email/URL normalization.
2. **LLM pass (~0.3–0.8 s for a typical utterance at 60–100 tok/s):** filler-word removal, **backtrack self-correction** ("coffee at 2 actually 3" → "coffee at 3"), list detection → formatted lists, tone matching per app category (Formal/Casual/Very-casual — bundle-ID → category map like Wispr's Flow Styles), light cleanup levels None/Light/Medium/High. Prompted with AX-derived context: app name, field content before cursor, selected text.
   - Always keep the verbatim transcript; show a diff on demand; "Undo AI edit" restores verbatim. This directly answers Wispr's biggest trust complaint.
   - Latency trick: the LLM pass runs on the *finalized* streaming text while the user is still releasing the key — partials give us a head start.

**System integration (all patterns validated against shipping apps)**

- **Hotkey:** CGEventTap (`.defaultTap`, Accessibility permission) watching `keyDown|keyUp|flagsChanged`. fn = `flagsChanged` keycode 63 / `.maskSecondaryFn`. Hold-to-talk with ~1 s interruption window (fn+arrow ≠ dictation); **double-tap fn (<350 ms) locks hands-free**; Esc cancels. Re-enable tap on `kCGEventTapDisabledByTimeout`. Onboarding sets `AppleFnUsageType=0` (Globe "Do Nothing") since Globe's system behavior can't be suppressed from a tap. Carbon `RegisterEventHotKey` shadow bindings under secure input. Also register a URL scheme (`plynn://toggle`) for Raycast/Shortcuts/BTT.
- **Insertion:** pasteboard-promise paste (Handy's pattern): save clipboard → set transcript with `org.nspasteboard.TransientType` + `ConcealedType` (clipboard managers skip it) → synthetic Cmd-V via CGEvents → **provide-data callback = read receipt** → restore clipboard guarded by `changeCount`. AppleScript key-code fallback for non-QWERTY. Optional per-app "type it" CGEvent mode for paste-hostile apps. One clean undo step.
- **Secure input:** poll `IsSecureEventInputEnabled()` at 1 Hz; momentary (password field) vs stuck (>3 s) states; never inject while active; indicator shows a lock state; help dialog identifies the culprit via `ioreg`.
- **Context:** `NSWorkspace.frontmostApplication` for app category; AX (`kAXFocusedUIElement` → value/selected-text/range) for field content — **no screenshots, no OCR** (VoiceInk's mistake, and Wispr's scandal). All context stays in-process and is never persisted.
- **Indicator:** non-activating borderless `NSPanel` (`.nonactivatingPanel`, `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `orderFrontRegardless`) — never steals focus from the target field. Live waveform → **live partial text** as you speak → brief "polished" state. Notch-aware bottom-center default, draggable/dockable, Liquid Glass styling on Tahoe.
- **Permissions onboarding:** Wispr's is best-in-class; copy the shape. Checklist screen (mic → accessibility → optional automation) with live polling, deep links, and a relaunch button (taps created pre-grant must be recreated). Use SpeechTranscriber as a zero-download engine so the user dictates successfully *within the first minute* while Parakeet downloads in the background. Escalating practice exercises.

---

## 4. Feature parity map (the small things)

From the Wispr inventory — each maps to a mechanism above:

- **Activation:** hold-fn PTT, double-tap hands-free lock (20-min cap + warning), rebindable multi-bindings incl. mouse buttons 4+, cancel/copy-last/paste-last shortcuts, whisper-mode (model handles quiet speech; Parakeet degrades gracefully).
- **Formatting:** auto punctuation/caps (native in Parakeet), filler removal, backtrack, list detection, spoken punctuation + "press enter", casual-app trailing-period drop, mid-sentence case merge, camelCase/snake_case + dev-jargon mode for terminals/IDEs.
- **Dictionary:** word boosting (decoder-level!), replacement rules, CSV import, ✨ **auto-learning from corrections** — post-paste, watch the field via AX for ~30 s, diff user edits against our output, propose dictionary entries (local learning loop nobody else has).
- **Snippets:** spoken trigger ≤60 chars → expansion ≤4k chars, mid-sentence, case-insensitive.
- **Context/tone:** per-app-category styles, respects existing field text, contact/proper-noun spelling from AX text (never OCR).
- **Commands:** Command Mode v1 — hold alt hotkey + speak over a selection ("make this more assertive", "translate to Spanish") → LLM transform in place with diff view; generation-at-cursor when nothing selected.
- **UI:** menu-bar app, Flow-bar-like indicator, history (searchable, grouped by day, audio replay N days, auto-delete policy), stats (WPM, streak, per-app words), Scratchpad later.
- **Integration:** every app via paste; retry ×5 → clipboard + toast fallback; works in terminals/Electron/browsers; URL scheme automation.

Deliberately dropped v1: teams, cross-device sync, meeting notetaker, mobile, MCP server, 100-language styles.

---

## 5. Build phases

**Phase 0 — Spike (validate the risky core, ~days):** bare app: fn-hold tap → AUHAL 16 kHz capture → FluidAudio Parakeet batch transcribe → pasteboard insert. Measure: release-to-paste latency, short-utterance (<2 s) correctness, RAM. *Go/no-go on the whole thesis.*

**Phase 1 — Reliable core loop:** Silero VAD gating, streaming partials in the indicator panel, session state machine (PTT/hands-free/cancel/interruption window), secure-input handling, permissions onboarding with SpeechTranscriber instant-start, model download manager, menu bar + settings skeleton. *Exit: daily-drivable raw dictation that never drops or truncates an utterance.*

**Phase 2 — Formatting layer:** rules pass; MLX Qwen3-4B runner in the XPC service; filler/backtrack/list/tone prompts; cleanup levels + diff + verbatim revert; per-app category map; AX context feed; head-start pipelining of partials. *Exit: output quality ≥ Wispr on your own daily use, blind-compared.*

**Phase 3 — Personalization:** dictionary UI + CTC boosting + CSV import, snippets, correction-watching auto-learn loop, history + stats (SQLite), Whisper/Qwen3-ASR max-accuracy pass option.

**Phase 4 — Command Mode & polish:** selection transforms with diff, generation at cursor, Liquid Glass indicator polish, Sparkle, notarized DMG, onboarding exercises, URL scheme, launch-at-login.

**Phase 5 — Later:** Scratchpad, meeting mode (FluidAudio diarization), possible fine-tuned small formatting model (distill the exact filler/backtrack/tone task into a 0.6–1.7B model for sub-200 ms polish), Windows/mobile never-or-much-later.

---

## 6. Risks

1. **LLM formatting latency/quality on-device** — the one thing genuinely unproven at Wispr quality. Mitigations: rules-pass-first design, partial-text head start, cleanup levels default Light, Foundation Models fallback, Phase-5 fine-tune. Phase 2 has an explicit blind-comparison exit gate.
2. **ANE contention** (FluidAudio ASR + Foundation Models both ANE) — solved structurally: LLM on GPU via MLX.
3. **Noisy/accented audio** below cloud quality — Whisper large-v3-turbo final pass; measure honestly.
4. **TCC/dev pain** — permissions are keyed to code signature; use a stable Dev ID cert from day one; `tccutil reset` scripts in the repo; Tahoe blocks synthetic events from ad-hoc-signed builds.
5. **Paste edge cases** — read-receipt pattern + per-app overrides + retry-then-clipboard fallback; build an app-compat test checklist (Terminal, iTerm, VS Code, Cursor, Slack, Notion, Safari, password managers).
6. **fn/Globe can't be fully intercepted** — onboarding must set the Globe default; offer non-fn defaults too.

## 7. Decisions (locked 2026-08-08)

1. **Name:** Plynn.
2. **License:** open source. MIT for our code (allows porting Handy's MIT patterns directly; keeps VoiceInk GPL code strictly read-only reference — no copying).
3. **Min macOS:** 26 (Tahoe) only — unlocks SpeechTranscriber, Foundation Models, Liquid Glass; minimal fallback code.
4. **Language:** English-first (Parakeet Unified EN default); multilingual via Parakeet v3 / Whisper pass in Phase 3+.

## 8. Reference material

- **FluidAudio** (github.com/FluidInference/FluidAudio, Apache-2.0) — ASR/VAD/boosting backbone.
- **Handy** (github.com/cjpais/Handy, MIT) — paste read-receipt (`paste_tx/macos.rs`), secure-input taxonomy (`secure_input.rs`). Safe to port.
- **VoiceInk** (github.com/Beingpax/VoiceInk, GPL-3) — read-only reference: `ShortcutMonitor.swift` (fn/modifier-only hotkeys), `CoreAudioRecorder.swift` (AUHAL), `CursorPaster.swift`.
- **WhisperKit** (Argmax, MIT) — accuracy-pass engine.
- **parakeet-mlx / mlx-lm** — prototyping + LLM runner.
- Apple: WWDC25 session 277 (SpeechAnalyzer), Foundation Models framework, TN2150 (secure input).
- Full research reports: Wispr feature inventory, local-ASR benchmarks, macOS integration, competitor analysis (in session research, summarized throughout this doc).
