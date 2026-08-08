# Plynn Phase 3a — Personalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans, task-by-task with TDD.

**Goal:** Plynn learns Carlton's world: a custom dictionary that fixes names/jargon the ASR mangles, spoken snippets that expand to canned text, and a local history with stats. All data in one SQLite file, fully local.

**Architecture:** `PersonalStore` (raw sqlite3, no deps) owns `terms`, `snippets`, `history`. Pipeline grows two pure stages: transcript → RulesFormatter → **SnippetExpander** → **DictionaryCorrector** → LLM (dictionary terms injected into prompt as preferred spellings). AppDelegate records every paste into history. UI: Dictionary + Snippets sections in Settings (CSV import for dictionary), History window from the menu bar with stats header.

**Constraint discovered:** FluidAudio's CTC vocabulary boosting lives on `SlidingWindowAsrManager` only — our streaming manager (`StreamingUnifiedAsrManager`) has no hook. Text-level correction now; ASR-level boosting deferred to a Phase 3b engine experiment.

**Deferred:** correction-watching auto-learn loop, Whisper accuracy pass, CTC boosting (3b).

### Task 1: PersonalStore (SQLite, TDD)
`Sources/PlynnKit/PersonalStore.swift`, tests against a temp-dir db.
- Raw `sqlite3` C API wrapper. Tables: `terms(id, text, aliases, created)`, `snippets(id, trigger, expansion, created)`, `history(id, ts, app, verbatim, formatted, duration_s, engine)`.
- CRUD for all three + `stats()` (session count, total words, total seconds) + `importTermsCSV(String) -> Int` (line = `term` or `term,alias1,alias2`; dedupe).
- Default path `~/Library/Application Support/Plynn/personal.db`; init takes explicit path for tests.

### Task 2: SnippetExpander + DictionaryCorrector (pure, TDD)
`Sources/PlynnKit/TextPersonalizer.swift`.
- `SnippetExpander.expand(_:snippets:)` — case-insensitive whole-phrase match of spoken trigger anywhere in text ("insert my email" style triggers are the user's choice; we match the trigger phrase literally), replace with expansion, preserve surrounding punctuation/case of neighbors.
- `DictionaryCorrector.correct(_:terms:)` — for each term, replace case-insensitive whole-word alias hits with the canonical text ("plin", "plyn" → "Plynn"); never replaces inside longer words.
- Both pure; tests cover multi-word triggers, punctuation adjacency, no-op safety.

### Task 3: Pipeline + prompt integration
- `TranscriptFormatter.format` gains `snippets`/`terms` (loaded once per call from an injected provider closure so Settings edits apply immediately): rules → snippets → dictionary → LLM.
- `LLMFormatter.prompt` gains optional `preferredSpellings: [String]` → "Prefer these exact spellings when the transcript approximates them: …".
- Non-LLM path still gets snippets + dictionary (deterministic).

### Task 4: History recording + UI
- AppDelegate paste effect → `store.record(...)` (app bundle ID, verbatim, formatted, duration, engine name).
- `HistoryWindow` (menu bar item "History…"): stats header (sessions, words, minutes dictated), searchable list, click row → copy formatted text. Delete-all button.
- Settings: Dictionary section (add/remove terms + aliases, Import CSV… via NSOpenPanel) and Snippets section (trigger → expansion table).

### Task 5: E2E validation (Carlton)
- Add "Plynn" with aliases, dictate "plin" → pasted text says Plynn.
- Snippet "my email" → carlton@charmtechnologies.co expands.
- History shows sessions with stats; CSV import works; everything survives relaunch.
