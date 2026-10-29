# Agents working on Reel

Reel records demos of macOS apps from a script, the way VHS records terminals: a `.tape` file says what to launch,
what to do and what to say, and reel plays it against the real app and writes a video with the app's sound, a GIF,
or both. Read `PLAN.md` first.

## Principles

- **The tape is the source of truth.** A demo is reproducible: change the app, run the tape again. Nothing about a
  take is decided interactively.
- **Record raw, render after.** `reel record` captures a take (the app's window and its audio, untouched, plus a
  timeline of what the tape did and when). `reel render` turns a take into the outputs. Overlays (captions, key
  badges, click ripples, zoom) are drawn at render time and anchored to timeline events, never to seconds, so a
  caption changes without recording again.
- **Apple frameworks only.** ScreenCaptureKit to capture, AVFoundation to write and export, Core Animation to draw,
  ImageIO for GIFs. No ffmpeg, no Node, no runtime dependencies to install next to the binary.
- **Domain in `ReelCore`, side effects at the edges.** The tape parser, the take format and the writer are in the
  core and tested without the screen; capture and app control need permissions CI does not have, so they stay thin.
- **Every error names its line.** A tape that does not parse says which line and why; nothing fails silently.

## Working

- `mise run test` and `mise run lint` before committing; `mise run fmt` fixes formatting.
- Capturing needs Screen Recording for the terminal reel runs in, and driving an app needs Accessibility. `reel doctor` reports both without asking for them.
- `mise run live` records `tapes/fixture.tape` against the fixture app for real and checks the take
  (`scripts/check-take.swift`): the window's size, silence before `Click "Play"` and 440 Hz after, and what the
  fixture logged. CI cannot run it. It plays a quiet tone and takes the mouse and keyboard for a few seconds.
- `mise run live-web` records `tapes/web.tape` against a local page in a browser reel starts (Chrome, Chromium,
  Brave, Edge or Playwright's download) and checks the take. It plays a quiet tone; the mouse stays yours.
- Branch names: `feature/`, `fix/`, `docs/`, `chore/`, `ci/`. Pull requests are squash-merged.
