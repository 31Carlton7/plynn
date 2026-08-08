# Plynn Phase 2 — Formatting Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The moat. Transform raw transcripts into polished text: an instant deterministic rules pass (spoken punctuation, "press enter", casing merge) plus a local LLM pass (Qwen3-4B via MLX on GPU) for filler removal, backtrack self-correction, list detection, and per-app tone — verbatim always kept.

**Architecture:** `Formatter` pipeline: transcript → `RulesFormatter` (pure, TDD) → optional `LLMFormatter` (MLXLLM `ChatSession`, GPU — never contends with ANE ASR) → `FormatResult {text, pressEnter, verbatim}`. `AppCategories` maps frontmost bundle ID → tone for the LLM prompt. AI polish is a Settings toggle; LLM failure/timeout falls back to rules-only output. Post-paste, `pressEnter` synthesizes Return.

**Tech Stack:** mlx-swift-examples 2.29.1 (MLXLLM/MLXLMCommon), Qwen3-4B-Instruct-2507-4bit (~2.3 GB, mlx-community), Swift 6.

**Deferred:** dictionary/snippets (Phase 3), AX field-content context + diff viewer UI (Phase 3/4), cleanup levels beyond on/off, partial-text head-start pipelining.

**Exit criteria:** "um so period new line first bullet" class inputs come out right; fillers/backtracks removed with AI polish on; casual apps get casual tone; LLM off/unavailable degrades gracefully; blind-compare vs Wispr on daily use reads at least as good.

---

### Task 1: RulesFormatter (pure, TDD)

**Files:** Create `Sources/PlynnKit/RulesFormatter.swift`; Test `Tests/PlynnKitTests/RulesFormatterTests.swift`

Handles what must be instant and deterministic:
- Spoken punctuation: period, comma, question mark, exclamation point/mark, colon, semicolon, em dash, hyphen, ellipsis, open/close quote(s), apostrophe s handling left alone. Tokens may arrive with model-attached punctuation ("period." → "."); replace word → symbol, then collapse `space-before-punctuation`, dedupe doubled sentence enders, and capitalize the next word after . ! ?
- "new line" / "next line" → `\n`; "new paragraph" → `\n\n`.
- Trailing "press enter" (also "hit enter") → stripped, `pressEnter = true`.
- Whitespace normalization; capitalize first character.

Tests (the spec — representative, not exhaustive):
```swift
("hello world period how are you", "Hello world. How are you")
("wait comma what question mark", "Wait, what?")
("first line new line second line", "First line\nSecond line")
("ship it press enter", "Ship it", pressEnter: true)
("one period. two period.", "One. Two.")   // model already attached periods
("em dash test em dash", "— test —")
```

### Task 2: AppCategories (pure, TDD)

**Files:** Create `Sources/PlynnKit/AppCategories.swift`; Test `Tests/PlynnKitTests/AppCategoriesTests.swift`

`enum Tone { casual, neutral, formal }`; `AppCategories.tone(forBundleID:)` with built-in map: casual = Messages/WhatsApp/Discord/Telegram/Slack; formal = Mail/Outlook/Gmail-PWAs; neutral default (terminals/IDEs also neutral + a `isTechnical` flag for camelCase-preservation prompt hint). Tests for representative IDs + default.

### Task 3: LLMFormatter (MLX, gated integration test)

**Files:** `Package.swift` (+mlx-swift-examples 2.29.1, product MLXLLM into PlynnKit); Create `Sources/PlynnKit/LLMFormatter.swift`; Test `Tests/PlynnKitTests/LLMFormatterTests.swift` (runs only with `PLYNN_LLM_TESTS=1` — 2.3 GB download + GPU)

- Actor; `ensureLoaded()` (ModelConfiguration id `mlx-community/Qwen3-4B-Instruct-2507-4bit`, `LLMModelFactory`/`ChatSession` per current MLXLLM API); `var ready: Bool`; `format(_ text: String, tone: Tone, technical: Bool) async throws -> String`.
- Prompt (system): "You clean up dictated text. Remove filler words (um, uh, like when meaningless). Apply self-corrections: 'coffee at 2 actually 3' → 'coffee at 3'. Format spoken lists as lists. Fix punctuation/capitalization. {tone line}. NEVER add content, NEVER answer questions in the text, NEVER explain. Return ONLY the cleaned text." User: the transcript. Strip whitespace/quotes from response; if response empty or >2.5x input length (runaway), return input unchanged.
- 3 s timeout via `Task` race → fall back to input.
- Integration test: filler+backtrack sample in → cleaned out (assert "actually" resolved, "um" gone).

### Task 4: Formatter pipeline + wiring

**Files:** Create `Sources/PlynnKit/Formatter.swift`; modify `Sources/Plynn/main.swift`, `Paster.swift` (add `pressReturn()`), `SettingsWindow.swift` (AI polish toggle + LLM status)

- `Formatter.format(transcript, bundleID, aiPolish) async -> FormatResult` = rules → (aiPolish && llm.ready ? llm : identity). `FormatResult { text, pressEnter, verbatim }`.
- AppDelegate: on `.stopAndTranscribe` completion, run Formatter before `.transcriptReady` (indicator stays in "Polishing…" during LLM); after paste, if pressEnter → `Paster.pressReturn()`. NSLog verbatim + formatted for the future diff/history.
- Settings: "AI polish" toggle (default on once model present), LLM status line (downloading/ready/off); background download kicked on first launch after Parakeet completes (serialize downloads).
- `swift test` green; sign; launch.

### Task 5: E2E validation (Carlton)

- "um so basically we should ship on friday actually monday" → AI polish → "We should ship on Monday." (or close)
- "first update the readme new line second fix the tests" → list/lines correct
- Slack message: casual tone (no trailing period on short msg); Mail: formal
- "lgtm press enter" in Slack → message sent
- AI polish off → rules-only output, instant
- Latency with polish: target ≤1.5 s release→paste on a 10 s utterance
