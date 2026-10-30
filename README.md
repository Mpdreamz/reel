<picture>
  <source media="(prefers-color-scheme: dark)" srcset="design/social/png/readme-banner-dark-1280x320.png">
  <img alt="reel: write a reel, get the video" src="design/social/png/readme-banner-light-1280x320.png">
</picture>

Demo videos of Mac apps and web pages, from a script. Like [VHS](https://github.com/charmbracelet/vhs), but for
windows instead of terminals, and with the app's sound.

**[Documentation](https://mpdreamz.github.io/reel/getting-started/)** ·
[Website](https://mpdreamz.github.io/reel/) ·
[Releases](https://github.com/Mpdreamz/reel/releases)

```sh
brew install --cask mpdreamz/tap/reel
reel doctor
```

macOS 15 or later, Apple silicon.

## A reel

```
Import //demos/reel.reelpreset
Launch ~/Projects/musicbox/build/App/Musicbox.app

Output //docs/media/musicbox.mp4
Output //docs/media/musicbox.gif
Set Size 1440x900
Intro@crossfade,ease-out,600ms 2s       # reel's sting, from the preset

Say "This is Musicbox, a sketchpad for chord progressions."
Say@over "Press space, [play] and every lane starts looping."
Wait [play]
Key space
Zoom #timeline.chords 1.8x
Say "The chords lane drives the others."
Zoom off
```

```sh
reel musicbox.reel    # record, then render every output
```

reel opens the app, plays the reel with a real cursor and real keys, records the window with the app's own sound,
and renders movies and GIFs with captions, narration, zooms and title cards. This one is
[reel's own demo](demos/musicbox.reel), recorded against Musicbox: its stings, its backgrounds and its five cuts,
for GitHub, the website, and three social shapes, come from [one preset](demos/reel.reelpreset).

Captions, zooms, speed-ups, cuts, title cards and every output setting are applied when rendering, so
`reel render musicbox.reel` picks up a change without recording again.

## What it does

- **Drives apps and web pages:** clicks, typing, keys, scrolling and waiting, by label or accessibility identifier.
  Web pages in WebKit, built in, or Chromium.
- **Narrates:** `Say` lines in a macOS or [voicebox](https://github.com/jamiepine/voicebox) voice, clicks landing on
  a word, the app's sound ducked underneath, subtitles for muted feeds.
- **Draws over it:** captions, key badges and click ripples.
- **Edits it:** zoom onto an element and follow it, speed through a stretch, cut what shouldn't be seen.
- **Frames it:** title cards, backgrounds, and 16:9, 1:1 and 9:16 canvases.
- **Fits it:** quality, codec and width; profiles for GitHub, the web and social feeds, each held to its size and
  length; presets to share it all between reels; conditions for what differs.

The [documentation](https://mpdreamz.github.io/reel/getting-started/) has the rest: a first reel, every command and
setting, and troubleshooting.

## From source

```sh
mise run install   # a release build into ~/.local/bin/reel
mise run test      # the tests
mise run docs      # the website and docs, on http://localhost:4000/reel/
```

[AGENTS.md](AGENTS.md) has the conventions; [PLAN.md](PLAN.md) the design and the reel language in full.

The brand (logo, icons, colours, fonts, themes) is in [design/brand](design/brand); its fonts are under the SIL Open
Font License.
