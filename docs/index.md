---
navigation_title: Home
description: "reel records demo videos of Mac apps and web pages from a script, with the app's sound, captions, narration and zoom."
---

# reel

Write a reel. Get the video.

reel records demos of Mac apps and web pages from a script. A reel is a short `.reel` file: what to open, what to
click and type, what to say. reel plays it against the real app, records the window with the app's own sound, and
renders a finished movie or GIF with captions, narration, zooms and title cards. Run it again when the app changes
and the demo is up to date.

```
Launch ~/Projects/musicbox/build/App/Musicbox.app
Output musicbox.mp4

Say "This is Musicbox, a sketchpad for chord progressions."
Key space
Zoom #timeline.chords 1.8x
Say "The chords lane drives the others."
Zoom off
```

It is to Mac apps what [VHS](https://github.com/charmbracelet/vhs) is to terminals.

## Where to go next

| | |
|---|---|
| [Getting started](getting-started/index.md) | Install reel, grant its two permissions, and record a first reel. |
| [Writing reels](reels/index.md) | How a reel is laid out, how it names what to click, and where its paths lead. |
| [Making a demo](demos/index.md) | Driving apps and web pages, narration, captions, zoom, speed-ups, cuts, and title cards. |
| [Outputs](outputs/index.md) | Quality and file size, framing for social, GIFs, profiles, presets and conditions. |
| [Reference](reference/index.md) | Every command, every setting, and the command line. |
| [Troubleshooting](troubleshooting.md) | When a reel stops, a window is the wrong size, or a file is too big. |
