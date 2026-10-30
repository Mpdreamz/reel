---
description: "An app reel drives the app with a real cursor and real keys, and stops rather than type into another app."
---

# Driving apps

```
Launch ~/Projects/musicbox/build/App/Musicbox.app
Output musicbox.mp4
Set Size 1440x900

Wait #lanes
Click "Play"
Type "C Am F G\n"
Key cmd+s
Scroll down 3 #list
Sleep 1s
```

`Launch` takes a bundle id (`com.apple.TextEdit`) or a path to an `.app` (anything with a slash: `./Musicbox.app`
beside the reel). reel opens it and waits for its first window and its accessibility tree.

| Step | Does |
|---|---|
| `Click <element or @x,y>` | Glides the cursor there and clicks. |
| `Type "<text>"` | Types a character at a time, pausing `TypingSpeed` (50 ms) after each; `Type@20ms "…"` for this line only. `\n` is return, `\t` tab. |
| `Key <combo> [count]` | `return`, `a`, `cmd+s`, `ctrl+shift+tab`, `f5`, `fn+left`; `Key down 3` presses it three times. |
| `Scroll <up\|down\|left\|right> [lines] [element or @x,y]` | Scrolls, over the element when one is named. |
| `Wait <element>` | Waits until the element shows, up to `WaitTimeout` (10 s). |
| `Sleep <duration>` | Waits. |

See [Elements](../reels/elements.md) for how to name what to click.

## Real input

The cursor glides to what it clicks and the click is real; keys are real key presses. A demo is meant to show a
person using the app, and a button that reacts with no cursor near it doesn't look like one. The cost is that a reel
takes the mouse and keyboard while it plays.

Before every input step reel checks that the app is in front. If it isn't, reel brings it back once; if that fails,
the reel stops, so typing never lands in another app.

## The window

`Set Size 1440x900` sizes the window, in points, before recording, and centres it on its screen. A tiling window
manager (yabai, Rectangle) may resize it straight back; reel reads the size again and warns. Let the app float while
the reel plays (with yabai: `yabai -m rule --add app='^Musicbox$' manage=off`).

The recording is the window alone, with the app's own sound: menus, sheets and popovers of the app show, other apps
don't. A window's rounded corners show what's behind them; framing the recording on a
[background](../outputs/framing.md) hides that.
