---
description: "Title cards before and after the demo, over a colour, an image or a video, with transitions."
---

# Intro and outro

```
Intro@slide-up,ease-out,700ms "Musicbox" "Chord progressions, sketched and heard"
Outro@fade,800ms "Recorded with reel" "brew install --cask mpdreamz/tap/reel"
Set IntroBackground //demos/backgrounds/intro-16x10.jpg
Set OutroBackground //demos/backgrounds/outro-16x10.jpg
```

| | |
|---|---|
| `Intro "<title>" ["<subtitle>"] [duration]` | A title card before the demo: 3 s, or a background video's own length. |
| `Outro "<title>" ["<subtitle>"] [duration]` | One after it. |
| `Intro [duration]`, `Outro [duration]` | No title: your own video on its own, such as a designed sting or a logo animation. |
| `Set IntroBackground <bg>`, `Set OutroBackground <bg>` | `#rrggbb`, an image (`.png`, `.jpg`, `.heic`) or a video (`.mov`, `.mp4`). A video's sound plays with it. Near-black unless set. |

Titles are centred, white with a soft shadow, sized from the video. A background fills the frame, cropped evenly.

## Your own video

An intro or an outro can be any video you made: a logo animation, a sting, a clip from somewhere else. Set it as the
background and leave out the title, and it plays as it is, with its sound:

```
Set IntroBackground //brand/intro.mp4
Set OutroBackground //brand/outro.mp4
Intro@crossfade
Outro@fade
```

reel's own demos open and close this way, on the stings in its brand kit. With a [condition](../outputs/conditions.md)
each cut can have its own: `Set IntroBackground social ? //brand/intro-9x16.mp4 : //brand/intro-16x9.mp4`.

## Transitions

`Intro@<kind>,<easing>,<duration>` says how the intro moves into the demo; on an outro, how the demo moves into it.

| Kind | |
|---|---|
| `crossfade` | The default, over 600 ms. |
| `fade` | Through black, half on either side of the cut. |
| `slide-left`, `slide-right`, `slide-up`, `slide-down` | Pushes one out as the other comes in. |
| `zoom` | Grows out of, or into, the demo. |
| `wipe-left`, `wipe-right`, `wipe-up`, `wipe-down` | Reveals the demo beneath. |
| `cut` | No transition. |

Any [easing](zoom-speed-and-trim.md) works: `Intro@slide-left,ease-out,800ms`. Titles move, or are wiped, with their
card, and the sound crosses the same way.

Intros and outros are render-only: a changed title, background or transition needs no new recording.
