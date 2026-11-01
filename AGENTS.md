# Agents working on Reel

Reel records demos of macOS apps from a script, the way VHS records terminals: a `.reel` file says what to launch,
what to do and what to say, and reel plays it against the real app and writes a video with the app's sound, a GIF,
or both. Read `PLAN.md` first.

## Principles

- **The reel is the source of truth.** A demo is reproducible: change the app, run the reel again. Nothing about a
  take is decided interactively.
- **Record raw, render after.** `reel record` captures a take (the app's window and its audio, untouched, plus a
  timeline of what the reel did and when). `reel render` turns a take into the outputs. Overlays (captions, key
  badges, click ripples, zoom) are drawn at render time and anchored to timeline events, never to seconds, so a
  caption changes without recording again.
- **Apple frameworks only.** ScreenCaptureKit to capture, AVFoundation to write and export, Core Animation to draw,
  ImageIO for GIFs. No ffmpeg, no Node, no runtime dependencies to install next to the binary.
- **Domain in `ReelCore`, side effects at the edges.** The reel parser, the take format and the writer are in the
  core and tested without the screen; capture and app control need permissions CI does not have, so they stay thin.
- **Every error names its line.** A reel that does not parse says which line and why; nothing fails silently.

## Working

- `mise run test` and `mise run lint` before committing; `mise run fmt` fixes formatting.
- Capturing needs Screen Recording for the terminal reel runs in, and driving an app needs Accessibility. `reel doctor` reports both without asking for them.
- `mise run live` records `reels/fixture.reel` against the fixture app for real and checks the take
  (`scripts/check-take.swift`): the window's size, silence before `Click "Play"` and 440 Hz after, and what the
  fixture logged. CI cannot run it. It plays a quiet tone and takes the mouse and keyboard for a few seconds.
- `mise run live-web` records `reels/web.reel` against a local page twice, in WebKit and in a Chromium-based browser
  (Chrome, Chromium, Brave, Edge or Playwright's download), and checks both takes. It plays a quiet tone; the mouse
  stays yours.
- `mise run demos` records reel's own demos (`demos/*.reel`, the Musicbox hero first) into `docs/media/`, which git
  ignores until the videos have a home. It plays music and takes the mouse and keyboard; CI only checks the reels parse.
- `mise run docs` builds the website as CI does (docs-builder over `docs/`, then `docs/reel-landing.html` over its
  home page, by `scripts/docs-landing.sh`) and serves it on http://localhost:4000/reel/. The `docs` workflow publishes
  it to GitHub Pages, mpdreamz.github.io/reel, on every push to main. A change to the reel language or the command line
  updates `docs/` in the same pull request, as it does PLAN.md. The landing page's video, `docs/landing/reel-demo.mp4`,
  and `reel-demo.gif` are the Musicbox demo's `web` cut: copy `docs/media/musicbox-web.mp4` and `.gif` over them
  after `mise run demos`. Its web pages video, `docs/landing/web-demo.mp4`, is the Commons demo's `web` cut
  (`docs/media/commons-web.mp4`), with `web-poster.jpg` a frame of it; its code video, `docs/landing/code-demo.mp4`,
  is the code demo's (`docs/media/code-web.mp4`), with `code-poster.jpg`; its command line video,
  `docs/landing/cli-demo.mp4`, is the terminal demo's (`docs/media/cli-web.mp4`), with `cli-poster.jpg`.
  `demos/tour.reel` joins the code and command line demos as scenes; it records nothing of its own.
- The code and terminal screens (`Screen code`, `Screen terminal`) are pages in `Sources/ReelCore/Resources/Screen`:
  `screen.html`/`screen.js` and `terminal.html`/`terminal.js`, the fonts, Monaco and xterm.js, which
  `scripts/vendor-monaco.sh` and `scripts/vendor-xterm.sh` download at a pinned version and checksum (bump both there
  and run it again; never edit `monaco/` or `xterm/` by hand). Nothing in the page may read the wall clock: animations
  are tweens on `screen.now`, which `pump` moves, or the same reel would draw different takes (`ScreenRecordingTests`
  and `TerminalRecordingTests` catch it). SwiftPM builds the page into `Reel_ReelCore.bundle`, which every way of
  installing reel puts beside the binary.
- The brand (logo, icons, colours, fonts, editor themes) is in `design/brand`, social images in `design/social`, the
  designed stings in `design/motion`; the demos' backgrounds in `demos/backgrounds`.
- Branch names: `feature/`, `fix/`, `docs/`, `chore/`, `ci/`. Pull requests are squash-merged.

## Releasing

Merges to main keep a draft release up to date (release-drafter; branch names set the label). `gh workflow run
release -f version=0.1.0` (or empty for the draft's version) builds main (`scripts/build-release.sh`, the version
written in and checked by `reel --version`, `Reel_ReelCore.bundle` beside it), signs it with the Developer ID and
notarizes it, attaches `reel-arm64.zip` (both, at its top) and its checksum to the draft, publishes it, and writes
`packaging/homebrew/reel.rb` to `mpdreamz/homebrew-tap`. A `dry_run` does everything but release, and keeps the zip
on the run. The secrets are stored with `scripts/release-secrets.sh` (run by the owner, never by an agent); without
them a release is ad-hoc signed and not sent to Homebrew. The `notary` workflow asks Apple about a slow or rejected submission; `tap` redoes the tap.

