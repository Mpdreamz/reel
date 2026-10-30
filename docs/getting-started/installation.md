---
description: "Install reel with Homebrew, or build it from source."
---

# Installation

reel is a command-line tool for macOS 15 or later on Apple silicon.

```sh
brew install --cask mpdreamz/tap/reel
reel doctor
```

`brew upgrade` updates it. Releases are signed with a Developer ID and notarized by Apple, so the binary runs without
a warning. The [releases](https://github.com/Mpdreamz/reel/releases) page has `reel-arm64.zip` and its checksum for
scripts.

Nothing else is needed: reel records with ScreenCaptureKit, encodes with AVFoundation and narrates with macOS's own
voices. Two things are optional:

- **[voicebox](https://github.com/jamiepine/voicebox)**, a local voice server, for narration in a cloned voice.
- **A Chromium-based browser** (Chrome, Chromium, Brave or Edge), for web tapes that ask for it with
  `Set Browser chromium`. WebKit is built in and the default.

## From source

You need Xcode and [mise](https://mise.jdx.dev).

```sh
git clone https://github.com/Mpdreamz/reel.git
cd reel
mise run install    # builds a release binary into ~/.local/bin/reel
```
