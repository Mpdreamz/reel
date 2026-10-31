---
description: "Driving apps, web pages and code, narration, captions and badges, zoom, speed-ups and cuts, and title cards."
---

# Making a demo

A demo is two things: a **take**, recorded once, and what is drawn over it and cut from it, applied each time you
render. That split decides what needs a new recording.

| Changing | Needs |
|---|---|
| What happens in the app: `Click`, `Type`, `Key`, `Scroll`, `Wait`, `Launch`, `Set Size` | A new take: `reel demo.reel` |
| A `Say` line's text, or the voice | A new take: the reel is timed by the narration |
| Which element a `Zoom` is on | A new take: recording finds the element |
| Captions, badges, ripples, subtitles | Only `reel render demo.reel` |
| Zooms on a point or the cursor, their scale and easing | Only a render |
| `Speed`, `Hide` and `Show` | Only a render |
| Intro, outro, backgrounds, framing | Only a render |
| Every output setting: quality, size, shape, GIFs, profiles | Only a render |
| On a [code screen](code.md): `Code`, `Go`, `Focus`, `Mark`, `Callout` | A new take, drawn in seconds without capturing anything |

`reel render` refuses a take whose actions no longer match the reel, and says which line changed.

| | |
|---|---|
| [Driving apps](driving-apps.md) | Real clicks, typing, keys and scrolling, and keeping the window the right size. |
| [Web pages](web-pages.md) | `Open` a page in WebKit or Chromium instead of launching an app. |
| [Code](code.md) | Walk through source in an editor of reel's own, with focus, marks and callouts. |
| [Narration](narration.md) | `Say` lines in a macOS or voicebox voice, timed to the clicks, with the app's sound ducked. |
| [Captions, badges and ripples](overlays.md) | What is drawn over the recording. |
| [Zoom, speed and trim](zoom-speed-and-trim.md) | Follow an element, speed through the boring part, cut what shouldn't be seen. |
| [Intro and outro](intro-and-outro.md) | Title cards over a colour, an image or a video, and the transitions into the demo. |
