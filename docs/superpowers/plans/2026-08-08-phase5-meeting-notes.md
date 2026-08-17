# Plynn Phase 5a — Meeting Notes

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans, task-by-task, TDD wherever logic is pure.

**Goal:** Triple-tap fn to start recording a meeting (mic **and** the other side of the call), triple-tap again to stop. Plynn transcribes the whole thing on-device, summarizes it into a clean Markdown note with the local model, saves both, and shows them in a Notes tab in the main window with a Markdown viewer and a full-transcript view.

**Decisions locked with Carlton (2026-08-08):** capture = mic + system audio; summarizer = Apple Intelligence with Qwen fallback (chunk-and-merge for long meetings); stop control = triple-fn (symmetric); trigger = triple-fn.

## Architecture

- **Capture:** `MeetingRecorder` on ScreenCaptureKit. One `SCStream` with `capturesAudio = true` (system) *and* `captureMicrophone = true` yields two time-aligned streams (`SCStreamOutputType.audio` / `.microphone`) — no separate AVAudioEngine, no manual clock alignment. Both are resampled to 16 kHz mono and **summed** into one track for the ASR (speaker attribution/diarization is a later phase). Requires the **Screen Recording** permission (SCK's audio tap needs it even with no video); we request it lazily on first meeting start and explain why in onboarding.
- **Transcription:** feed the summed 16 kHz stream into the existing `StreamingTranscriber` (Parakeet), exactly like dictation but long-running. Partial text is buffered into a transcript with coarse timestamps every ~30 s of audio.
- **Summarization:** `MeetingSummarizer` builds a Markdown note (title, TL;DR, key points, decisions, action items). Apple Intelligence has a ~4k-token context, so transcripts are split into ~2.5k-token chunks, each summarized to bullets, then a final pass merges bullets into the note. Same `PolishPrompt.sanitize` guards. Falls back to Qwen; degrades to "transcript only, summary pending" if no engine.
- **Storage:** new `meetings` table in `PersonalStore` (id, started, duration_s, title, transcript, notes_md, status). Also written to `~/Library/Application Support/Plynn/Meetings/<date>-<title>.md` so notes are plain files the user owns.
- **Trigger:** `Session` state machine gains a **triple-tap** detector layered *on top of* the existing double-tap hands-free lock. Third fnDown within `doubleTapWindow` of the hands-free lock **cancels the hands-free session** and starts a meeting instead (so hands-free still works: it simply becomes "meeting" if a third tap arrives). Triple-tap while a meeting is running stops it. Pure logic → TDD.
- **UI:** the pill gets a `.meeting(elapsed:)` phase (red dot, mm:ss, "Recording meeting"). Main window gets a **Notes** tab: list of meetings → detail with a segmented control **Notes / Transcript**; Notes renders Markdown (SwiftUI `Text(AttributedString(markdown:))` blocks per paragraph — no third-party dependency), Transcript is a monospaced scroll with timestamps. Copy and Reveal-in-Finder buttons.

## Tasks

### 1. Triple-tap in Session (pure, TDD)
`Session.swift`, `SessionTests.swift`. New states `.meeting`, events `.meetingStop`, effects `.startMeeting` / `.stopMeeting`. Tests: triple-tap from idle → `.startMeeting` and hands-free is *not* left running; double-tap alone still locks hands-free (regression); triple-tap during meeting → `.stopMeeting`; escape during meeting → `.stopMeeting` (keep the recording; never discard a meeting on escape).

### 2. Transcript model + MeetingSummarizer prompt (pure, TDD)
`MeetingTranscript` (segments with offsets, `markdown` rendering), `MeetingSummarizer.chunk(_:maxTokens:)` (splits on sentence boundaries, never mid-sentence) and prompt builders. Tests: chunking respects boundaries and cap; merged prompt includes every chunk's bullets; sanitize reuse; empty transcript → no summary call.

### 3. PersonalStore meetings table (TDD)
`addMeeting / updateMeeting / meetings() / meeting(id:) / deleteMeeting`, plus `writeMarkdownFile`. Tests mirror the history tests.

### 4. MeetingRecorder (ScreenCaptureKit)
`MeetingRecorder.swift`: request SCK permission, build content filter (all displays, exclude own process audio), start stream with audio + mic, `SCStreamOutput` handler resamples both to 16 kHz mono and sums, `onChunk` callback + elapsed timer. No unit tests (system-dependent); a gated manual test records 5 s and asserts non-empty samples.

### 5. Wiring + pill state
AppDelegate: `.startMeeting` → MeetingRecorder + StreamingTranscriber feed, pill `.meeting`; `.stopMeeting` → finish transcript, save row (status recording→summarizing), run summarizer in background, update row + write .md, pill shows brief "Notes saved" done state. Menu bar gets "Start Meeting Notes" as a mouse alternative to triple-fn.

### 6. Notes tab UI
`MeetingsView` (list + detail, Notes/Transcript segmented control, Markdown renderer, copy/reveal), added to `MainView` tabs and `plynn://notes`. Empty state explains the triple-tap.

### 7. E2E validation (Carlton)
Triple-fn during a real FaceTime/Zoom call → both sides transcribed; stop → note appears within ~a minute with sensible TL;DR / action items; .md file exists; hands-free double-tap still works exactly as before; Screen Recording permission flow reads clearly on first use.

**Deferred:** speaker diarization (FluidAudio Sortformer — Phase 5b), live "notes so far" during the meeting, calendar-title auto-naming, export to Notes/Obsidian.
