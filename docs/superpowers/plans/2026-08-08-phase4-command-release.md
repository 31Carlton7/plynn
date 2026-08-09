# Plynn Phase 4 — Command Mode + Release Tooling

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans, task-by-task with TDD where logic is pure.

**Goal (two tracks, per Carlton):**
- **A — Command mode:** select text anywhere, hold fn, speak an instruction ("make this shorter", "fix the grammar", "translate to French") → the selection is replaced with the transformed text. v1 auto-applies (Cmd-V naturally replaces a selection); diff-preview UI is a follow-up.
- **B — Release tooling:** DMG packaging, `plynn://` URL scheme, notarization script (submission needs Carlton's Apple ID credentials), Sparkle auto-update (deferred until appcast hosting + EdDSA keys are decided with Carlton).

### Track A

**A1 — SelectionReader (AX):** `Sources/PlynnKit/SelectionReader.swift` — read `kAXSelectedTextAttribute` from the focused element (nil for secure fields / no selection / empty). Thin AX wrapper, no unit tests (system-dependent); logic-free.

**A2 — TransformPrompt (pure, TDD):** `Sources/PlynnKit/TransformPrompt.swift` — builds the instruction prompt: selected text fenced as `<text>`, spoken instruction fenced as `<instruction>`, rules (apply the instruction to the text, output only the result, preserve meaning otherwise, never answer/comment). Shares `PolishPrompt.sanitize` guards. Tests: prompt contains both payloads; sanitize reuse.

**A3 — Command mode wiring:** in `startRecording`, capture `SelectionReader.selectedText()`. At transcript completion, if a selection was captured and the transcript is non-empty → command path: `AppleFMFormatter`/`LLMFormatter` runs the transform prompt (8 s timeout, fallback = do nothing rather than paste garbage), result goes through the normal paste (replaces the selection). Indicator shows "Rewriting…" phase label during the transform. History records it with engine tag "command".

**A4 — E2E validation (Carlton):** select a paragraph, hold fn, "make this shorter" → replaced in place; "fix the grammar"; no-selection dictation still works identically; LLM-unavailable → selection untouched, no paste.

### Track B

**B1 — DMG script:** `scripts/make-dmg.sh` — build `--install`-style app → staging dir with `Applications` symlink → `hdiutil create` UDZO `build/Plynn.dmg`. No notarization dependency; runs today.

**B2 — URL scheme:** `plynn://settings|history|dictionary` — CFBundleURLTypes in Info.plist + `application(_:open:)` routing to the existing window controllers.

**B3 — Notarization script (not runnable without credentials):** `scripts/notarize.sh` — `xcrun notarytool submit --keychain-profile plynn-notary --wait` + staple; README section documents the one-time `notarytool store-credentials` step Carlton must run.

**B4 — Sparkle (deferred decision):** needs appcast hosting choice (GitHub Releases raw URL works) + EdDSA key generation + framework embedding in make-app.sh. Parked until Carlton picks hosting; tracked on ROADMAP.

**Exit criteria:** command transforms work in TextEdit/Slack/Notes; `make-dmg.sh` produces a mountable drag-install DMG; `plynn://history` opens History; notarize.sh documented.
