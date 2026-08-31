# Plynn

![Plynn: free, open source, 100% on-device dictation](docs/assets/hero.png)

Dictation for your Mac that never touches the internet. Hold the fn key, talk, release, and clean text appears wherever your cursor is. Every part of it (speech recognition, AI cleanup, your dictionary, your history) runs on your Mac's own silicon.

I built this because I loved what Wispr Flow could do but didn't love sending my voice to a server to do it. Turns out Apple Silicon is fast enough that you don't have to.

## What it does

- **Hold fn and talk.** Live transcript streams into a floating glass pill while you speak. Release and it pastes. On an M-series Mac the paste lands in well under a second for typical dictations.
- **AI polish, on-device.** Fillers removed, self-corrections applied ("ship friday actually monday" becomes "ship on Monday"), spoken lists formatted, tone matched to the app you're in. Casual in Messages, proper in Mail. Runs on Apple Intelligence, with a local Qwen fallback.
- **Command mode.** Select any text, hold fn, and say what to do with it: "make this shorter", "fix the grammar". The selection gets replaced in place.
- **It learns your words.** Add names and jargon to your dictionary (or import a CSV), and when you fix a word right after a paste, Plynn notices and learns the correction on its own.
- **Snippets.** Say "my email" and your actual email comes out.
- **History and stats**, stored in a local SQLite file you can open yourself.
- Spoken punctuation, "new line", "press enter" to auto-send, secure-field detection so it never types into password boxes.

## Install

Grab it at [plynn.vercel.app](https://plynn.vercel.app), or grab `Plynn.dmg` from [Releases](../../releases), drag Plynn to Applications, and launch. The app is notarized, so there's nothing to bypass. Onboarding asks for microphone and accessibility permissions, and the speech models (about 1 GB) download in the background while Apple's built-in engine covers your first dictations.

Requires macOS 26 (Tahoe) on Apple Silicon. Enable Apple Intelligence in System Settings to get the best polish engine.

## Build from source

```bash
git clone https://github.com/31Carlton7/plynn.git
cd plynn
./scripts/make-app.sh
```

You'll need Xcode 26 with the Metal toolchain component (`xcodebuild -downloadComponent MetalToolchain`). The build uses `xcodebuild` rather than plain `swift build` because the MLX Metal shaders require it. `swift test` runs the unit tests.

### Startup recovery

Plynn prepares the local speech engine in the setup window. The first run can
take longer while speech models download; later launches warm the cached model.
If cached model startup times out, the setup window tells you to relaunch
Plynn. A transcript is copied to the clipboard when the focused field cannot
be safely targeted, so you can press `⌘V` manually.

### Optional Codex CLI context

Plynn can resolve spoken filenames against the local repository used by Codex CLI. Source `scripts/plynn-codex-context.zsh` from your `~/.zshrc`, then launch Codex with `plynn_codex` instead of `codex`:

```zsh
source /path/to/plynn/scripts/plynn-codex-context.zsh
plynn_codex
```

The bridge shares the workspace path only. Plynn indexes bounded, unique filenames locally; it does not read file contents or send context over the network.

## How it's put together

Speech recognition is Parakeet Unified running on the Neural Engine via [FluidAudio](https://github.com/FluidInference/FluidAudio), streaming partials as you speak. A deterministic rules pass handles spoken punctuation instantly, then a small on-device language model does the heavier cleanup, but only when the transcript actually needs it. Clean short dictations skip the model entirely and paste immediately. A latency gate, basically.

Your dictionary, snippets, and history live in one SQLite file at `~/Library/Application Support/Plynn/`. Dictation text stays on the Mac; first use downloads the local speech and polish models. There's no account, no telemetry, and no transcript upload.

See [ROADMAP.md](docs/ROADMAP.md) for what's next, including swappable polish models.

## License

MIT. See [LICENSE](LICENSE).
