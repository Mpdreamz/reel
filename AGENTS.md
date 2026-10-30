# Agents working on Reel

Reel records demos of macOS apps from a script, the way VHS records terminals: a `.reel` file says what to launch,
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
- `mise run live` records `tapes/fixture.reel` against the fixture app for real and checks the take
  (`scripts/check-take.swift`): the window's size, silence before `Click "Play"` and 440 Hz after, and what the
  fixture logged. CI cannot run it. It plays a quiet tone and takes the mouse and keyboard for a few seconds.
- `mise run live-web` records `tapes/web.reel` against a local page twice, in WebKit and in a Chromium-based browser
  (Chrome, Chromium, Brave, Edge or Playwright's download), and checks both takes. It plays a quiet tone; the mouse
  stays yours.
- `mise run demos` records reel's own demos (`demos/*.reel`, the Musicbox hero first) into `docs/media/`, which git
  ignores until the videos have a home. It plays music and takes the mouse and keyboard; CI only checks the tapes parse.
- Branch names: `feature/`, `fix/`, `docs/`, `chore/`, `ci/`. Pull requests are squash-merged.

## Releasing

Merges to main keep a draft release up to date (release-drafter; branch names set the label). `gh workflow run
release -f version=0.1.0` (or empty for the draft's version) builds main (`scripts/build-release.sh`, the version
written in and checked by `reel --version`), signs it with the Developer ID and notarizes it, attaches `reel-arm64.zip`
and its checksum to the draft, publishes it, and writes `packaging/homebrew/reel.rb` to `mpdreamz/homebrew-tap`. A
`dry_run` does everything but release, and keeps the zip on the run. The secrets are stored with
`scripts/release-secrets.sh` (run by the owner, never by an agent); without them a release is ad-hoc signed and not
sent to Homebrew. The `notary` workflow asks Apple about a slow or rejected submission; `tap` redoes the tap.

