---
description: "Captions, key badges, click ripples and the cursor, drawn over the recording when rendering."
---

# Captions, badges and ripples

```
Click "Play"
Caption "Every lane starts looping"
Sleep 2s
Key cmd+s
Caption "Saved" 1.5s
Caption off
```

| | |
|---|---|
| `Caption "<text>"` | Shows the text along the bottom, from here until the next caption. |
| `Caption "<text>" <duration>` | For that long at most. |
| `Caption off` | Ends the caption showing. |
| `Set KeyBadges on\|off` | A badge for each `Key` step, such as `⌘S` or `↓ ×3`, from the key press until 0.6 s after it. On unless set. |
| `Set ClickRipples on\|off` | A ripple where each click lands, for 0.5 s. On unless set. |

Captions aren't recorded. Each one is placed at the end of the action before it in the take, so you can add, move,
reword or remove captions and render again without a new recording. Text is sized from the video, so a caption
reads the same in a GIF 720 wide as in a 4K movie.

Captions and badges stay put when the picture [zooms](zoom-speed-and-trim.md); a ripple moves with the zoom to where
its click shows.

## The cursor

An app reel records the real cursor. A web reel draws an arrow along the path reel moved it, through cuts,
speed-ups and zooms.

```
Set Cursor off
```

`Set Cursor off` leaves the cursor out, for a page where none should show, such as an animated title page. In a web
reel it is drawn at render time, so it changes without a new recording, and a profile or a
[condition](../outputs/conditions.md) can set it. In an app reel the real cursor is part of the recording: the
setting takes effect at the next recording, and is the same for every profile. Clicks still land, and their ripples
still show unless `Set ClickRipples off`; `Zoom cursor` still follows the hidden cursor.

Code and terminal screens have no cursor to hide. Their caret is part of the screen, and stays.
