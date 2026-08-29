# Installing Plynn

## For users

1. **Download** `Plynn.dmg` from GitHub Releases (a Homebrew cask is on the way).
2. **Drag Plynn to Applications.** Standard DMG window with an Applications shortcut.
3. **First launch.** Gatekeeper checks the notarization ticket, so there are no warnings to click through.
4. **Onboarding** walks you through the two permissions Plynn needs:
   - **Microphone** (a system prompt) so it can hear you.
   - **Accessibility** (a System Settings deep link) for the fn hotkey and pasting.
5. **Models download in the background**, about 3 GB total: the Parakeet recognizer first, then the polish model. Dictation works the moment Parakeet lands (about 1 GB), and Apple's built in engine covers the gap before that.
6. Optional: turn on **Launch at login** in Settings.

Updates arrive through Sparkle: the app tells you when a new version exists and installs it in one click.

## Release engineering

- `make-app.sh` builds with `swift build` (Command Line Tools on Sequoia 15 / Intel) and ad-hoc signs `build/Plynn.app`.
- `notarize.sh` submits to Apple with `notarytool` and staples the ticket.
- `make-dmg.sh` packages the drag to Applications DMG. Pass `SKIP_BUILD=1` after notarizing so the stapled app is packaged as is.
- `make-release.sh` runs the whole chain and publishes the GitHub release with a signed Sparkle appcast.

## For development

```bash
./scripts/make-app.sh            # build + sign into build/Plynn.app
./scripts/make-app.sh --install  # and replace /Applications/Plynn.app
```

Permissions survive reinstalls because macOS keys them to the bundle ID and the stable Developer ID certificate, not the binary hash.
