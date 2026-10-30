---
description: "Quality, codec, width and frame rate, and fitting a movie or GIF under a size limit."
---

# Quality and size

A screen recording is mostly still, so it compresses well. reel encodes every movie once, from a lossless render, as
the tape says:

| Setting | Default | |
|---|---|---|
| `Set Quality <1–100>` | 65 | The encoder's quality, not a bitrate. 65 looks sharp and is a fraction of the size of the best. |
| `Set Codec h264\|hevc\|prores` | `h264` | H.264 plays everywhere. HEVC is about half the size and plays on Apple devices and in most current browsers. ProRes is lossless for editing, in a `.mov`; an `.mp4` gets H.264 at quality 100 instead. |
| `Set VideoWidth <pixels>` | full size | Scales movies down to this width, never up. A Mac records at Retina size, twice the points. |
| `Set VideoFrameRate <n>` | as recorded | Fewer frames a second, at most the recording's. |

Every output says what it came out as:

```
wrote docs/media/musicbox-github.mp4 (5.6 MB, H.264 1920x1256, quality 65)
```

On a 23 second demo recorded at 3124 pixels wide, quality 65 made 10.3 MB; 1920 wide, 5.5 MB; HEVC at 1920 wide,
3.9 MB.

## Fitting under a size

```
Set MaxSize 10MB
Set MaxLength 2m
```

`MaxSize` is the most an output may be: `10MB`, `500KB`, `1.5GB`, counted in thousands as upload limits are.
`MaxLength` is the longest it may run; a longer one fails the render.

A movie is encoded at its quality first. When it comes out over the size, it is encoded again at the bitrate the
size leaves for its length, after the sound, and each later try aims from how the last two came out. When that
bitrate would be too little for the picture, it drops to 30 frames a second, then narrows the picture. At most four
encodes; if it still doesn't fit, the render fails, says the size it reached and what to lower, and leaves no file.

```
wrote musicbox.mp4 (1.6 MB, H.264 1998x1306, 30 fps, 0.7 Mbit/s to fit 2.0 MB, 3 encodes)
```

A GIF over its size is drawn again with fewer colours (128, then 64), then fewer frames (10 a second), then
narrower; all at once when it's far over. At most six tries.

The [profiles](profiles.md) set these for where a video is going: `github` holds a movie and a GIF to GitHub's
10 MB.
