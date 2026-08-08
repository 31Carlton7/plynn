# Installing Plynn

## For users (the eventual flow)

1. **Download** `Plynn.dmg` from GitHub Releases (or `brew install --cask plynn`).
2. **Drag Plynn to Applications** — standard DMG window with an Applications shortcut.
3. **First launch** — Gatekeeper checks the notarization ticket; no warnings because the app is Developer ID signed and notarized.
4. **Onboarding** walks through the two permissions Plynn needs:
   - **Microphone** (system prompt) — to hear you.
   - **Accessibility** (System Settings deep link) — for the fn hotkey and pasting.
5. **Models download in the background** (~3 GB total: Parakeet ASR then Qwen3-4B polish). Dictation works the moment Parakeet lands (~1 GB); Apple's built-in engine covers the gap before that. AI polish switches on automatically when Qwen finishes.
6. Optional: enable **Launch at login** in Settings.

Updates ship via **Sparkle** (Phase 4): in-app "a new version is available," delta updates, signed appcast.

## Release engineering (what we build, Phase 4)

- `make-app.sh` → `xcodebuild` (Metal shaders require it) → signed .app with SPM resource bundles in `Contents/Resources`.
- `xcrun notarytool submit` + `xcrun stapler staple` for notarization.
- `create-dmg` (or `hdiutil`) for the drag-to-Applications DMG.
- GitHub Actions release workflow + Homebrew cask once public.

## For development

```bash
./scripts/make-app.sh            # build + sign into build/Plynn.app
./scripts/make-app.sh --install  # …and replace /Applications/Plynn.app
```

Permissions survive reinstalls because TCC grants key on the bundle ID + the stable Developer ID signing certificate, not the binary hash.
