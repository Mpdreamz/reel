---
description: "Join reels into one video: an app, a web page, code and the command line, with transitions between them."
---

# Scenes

```
Import //demos/house.reelpreset
Include app.reel
Include@slide-left web.reel
Include@crossfade,800ms code.reel
Include@cut cli.reel

Output tour.mp4
Output tour.gif
Intro "Musicbox" "From the app to the code"
Outro "Recorded with reel"
```

A reel records an app, a web page, a [code screen](code.md), a [terminal](terminal.md), or
[several of them at once](together.md). To show them one after the other in a video, write each as a reel of its own,
a **scene**, and join them with `Include`. Each scene keeps everything its own reel has: its narration, captions,
badges, zooms, speed-ups and cuts.

| Command | |
|---|---|
| `Include <scene.reel>` | The first scene, and what makes this reel a sequence of them. After any `Import` lines. |
| `Include@<transition> <scene.reel>` | The next scene, moving in from the one before: `crossfade` (the default, 600ms), `fade`, `slide-left` and the other slides, `zoom`, the wipes, or `cut`; with an easing and a duration, as an [intro](intro-and-outro.md) takes them. |

A scene can be included more than once. It can't join scenes itself.

A [reel of tracks](together.md) is a scene like any other. It records all its tracks at once, as it does on its own.
In the sequence, its tracks are drawn together on the sequence's canvas and backdrop, laid out and moved as its
director says, with the director's narration and captions over them.

## Recording and rendering

`reel tour.reel` records every scene in order, each into its own take next to its own reel, then renders the
sequence. `reel record tour.reel` only records them; a scene can also be recorded on its own, with
`reel record app.reel`. `reel render tour.reel` joins the takes the scenes have, and says which scene has none yet.

Changing one scene needs only that scene recorded again. Changing what is drawn over a scene (captions, zooms) needs
only a render, as it does for the scene on its own.

## What the sequence decides

A sequence has no steps of its own, and it doesn't record anything, so the settings that are fixed when recording
(`Voice`, `FrameRate`, `Viewport` and the rest) belong in the scenes and are refused in the sequence. A preset it
imports may still set them, for the scenes that import it too.

The sequence's own say how the whole video looks:

- its **Outputs**, **profiles** and every output setting (quality, sizes, GIFs);
- its **Intro** and **Outro**, around all of it. A scene's own intro and outro are left out;
- its **framing**. Scenes differ in size, so they always sit on a canvas: the Output's shape (`Output@9:16 …`,
  `Set Shape`), 16:9 when it has none, on the sequence's `Set Background` and `Padding`. Every scene is fitted on the
  same canvas, the largest any of them needs.

Rendered for a profile, each scene is read for the same profile when it knows one by that name, so a scene's own
`Profile social` or a condition such as `Caption social ? "short" : "a longer caption"` applies in the sequence's
`social` cut.
