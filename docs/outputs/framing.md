---
description: "The recording on a background, with padding, rounded corners and a shadow, in 16:9, 1:1, 9:16 or an exact size."
---

# Framing

```
Set Background //demos/backgrounds/backdrop-16x10.jpg
Set Padding 6%
Output@16:9 wide.mp4
Output@1080x1920 vertical.mp4
```

Framed, the recording sits centred on a canvas with padding around it, rounded corners and a soft shadow, over a
background. An output is framed when it has a shape, or every output once the reel sets a background.

| | |
|---|---|
| `Output@<shape> <path>` | This output on a canvas: an aspect (`@16:9`, `@1:1`, `@9:16`) or an exact size in pixels (`@1080x1920`). |
| `Set Shape <shape>` | Every output that names no shape of its own. |
| `Set Background <bg>` | `#rrggbb`, an image, or a video (looped, silent). |
| `Set Padding <n%>` | Room around the recording, as a share of the canvas's shorter side: 6% unless set, up to 30%. |

At an aspect the canvas is the smallest that holds the recording at its own size with the padding, at most 3840
pixels on its longer side. An exact size fits the recording in, which is what a platform that wants 1080x1920 needs.

An intro and an outro fill the whole canvas around the framed demo.

A landscape app on a 9:16 canvas is mostly background. [Zoom](../demos/zoom-speed-and-trim.md) is what makes a
vertical cut work.
