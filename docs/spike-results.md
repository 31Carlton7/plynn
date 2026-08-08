# Phase 0 Spike Results

Run date: __________  Machine: M4 Pro / 24 GB / macOS 26.4

## Setup checklist

- [ ] `open build/Plynn.app`
- [ ] System Settings → Privacy & Security → **Accessibility** → enable Plynn
- [ ] Quit (`pkill -x Plynn`) and relaunch (`open build/Plynn.app`) — the tap must be recreated after the grant
- [ ] First fn-hold: grant the **Microphone** prompt
- [ ] System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing** (or run: `defaults write com.apple.HIToolbox AppleFnUsageType -int 0` and log out/in)
- [ ] Logs: `log stream --predicate 'process == "Plynn"' --style compact` (or run `build/Plynn.app/Contents/MacOS/Plynn` directly in a terminal tab to see NSLog on stderr)

## Dictation runs (fill in from log lines)

| # | Utterance | Audio (s) | Latency (release→paste) | Pasted OK? | Transcript errors |
|---|---|---|---|---|---|
| 1 | "Testing" (short) | | | | |
| 2 | "Yes" (short) | | | | |
| 3 | "Sounds good, see you at three" (short) | | | | |
| 4 | Sentence with a name + number | | | | |
| 5 | Two-sentence Slack-style message | | | | |
| 6 | ~10 s continuous thought | | | | |
| 7 | ~20 s rambling paragraph | | | | |
| 8 | "push the branch to GitHub and rebase onto main, then run swift test" | | | | |
| 9 | Speaking fast | | | | |
| 10 | Speaking quietly | | | | |

Also verify: hold fn + press an arrow key → must log "hold interrupted", no paste.

## Metrics

- RSS after model warm: ______ MB (target < 2 GB; startup measured at 30 MB pre-model)
- RSS after 10 dictations: ______ MB
- Latency on the 10 s utterance: ______ (go/no-go: < 1.0 s; expect ~0.3–0.5 s)
- Empty/truncated transcripts: ______ / 10 (go/no-go: 0)

## Verdict

- [ ] GO — proceed to Phase 1
- [ ] NO-GO — notes:

## Notes / feel
