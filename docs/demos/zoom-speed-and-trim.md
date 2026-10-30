---
description: "Zoom onto an element and follow it, speed through a stretch, and cut what shouldn't be seen."
---

# Zoom, speed and trim

## Zoom

```
Zoom #timeline.chords 1.8x
Say "The chords lane drives the others."
Zoom cursor
Zoom@ease-out,600ms @400,300 2x
Zoom off
```

| | |
|---|---|
| `Zoom <element> [scale]` | Zooms onto the element and stays locked on it, following it if it moves, until the next `Zoom`. Without a scale it is fitted with room around it, at most 4×. |
| `Zoom @x,y [scale]` | Onto a point, 2× unless a scale is given. |
| `Zoom cursor [scale]` | Follows the cursor, smoothed over 0.3 s so it glides rather than jitters. |
| `Zoom off` | Back to the whole window. |
| `Zoom@<easing>,<duration> …` | This zoom's own move: `Zoom@ease-out #list`, `Zoom@600ms off`, `Zoom@smooth,1s cursor`. |

Scales run from 1× to 8×. The zoomed region keeps the window's shape and stays inside it. reel says so when an
element nearly fills the window, so fitting it hardly zooms.

Moves take `ZoomDuration` (400 ms) with `ZoomEasing` (`ease-in-out`) unless the tape or the zoom says otherwise:

| Easing | Moves |
|---|---|
| `linear` | At an even pace. |
| `ease-in`, `ease-out`, `ease-in-out` | Starting slow, ending slow, or both. |
| `smooth` | Half a sine: gentle at both ends. |
| `snap` | Not at all: it jumps. |

A zoom on an element is found while recording, so changing which element needs a new take; its scale and easing
change with a render. Zooms on a point or the cursor are render-only.

## Speed

```
Speed 4x
Click "Export"
Wait "Done"
Speed off
```

The stretch plays faster, above 1× up to 16×. Narration keeps its own pace, and the app's sound is left out of a
sped-up stretch, where it would only be noise.

## Trim

```
Hide
Wait "Library"
Sleep 1s
Show
```

The stretch is left out of the video. A `Hide` with no `Show` runs to the end. A cut that would split a narrated line
is refused.

Speed and trims take effect at the end of the action before them, like captions, and change with a render. Everything
timed (captions, narration, ducking, zooms) moves with the cut; `.reel/<tape>/edit.json` says what was kept and how
fast.
