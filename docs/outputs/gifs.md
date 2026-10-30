---
description: "GIFs are drawn from the rendered movie, with still stretches merged into one frame."
---

# GIFs

```
Output demo.gif
Set GifWidth 720
Set GifFrameRate 12
Set GifColors 128
```

| Setting | Default | |
|---|---|---|
| `Set GifWidth <pixels>` | 800 | 100 to 4000, never wider than the video. |
| `Set GifFrameRate <n>` | 15 | Frames a second, 1 to 50. |
| `Set GifColors <n>` | 256 | 2 to 256. One palette serves every frame, so colours don't flicker. Fewer make a smaller file. |

A GIF is drawn from the same lossless render as the movies, overlays included, and loops forever. A demo is mostly
still, so frames that look the same as the one before are merged into one longer frame: on a typical demo about a
third of the sampled frames are kept. Frame times add up exactly to the movie's length.

A GIF has no sound. [Subtitles](../demos/narration.md) are how narration reaches one.
