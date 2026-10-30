---
description: "When a reel stops, a window is the wrong size, an element isn't found, or a file is too big."
---

# Troubleshooting

## Start with reel doctor

```sh
reel doctor
```

It says whether Screen Recording and Accessibility are granted, and to which terminal they need to be granted: the
one reel runs in. After granting one, quit and reopen that terminal.

## The reel stopped: the app isn't in front

reel checks the app is in front before every input step, and stops rather than type into another app. Something
took focus: a notification, a dialog, another app opening. Leave the Mac alone while an app reel plays.

## The window is the wrong size

```
warning: the window is 1000x900, not 1440x900: the app limits its size, or a window manager (yabai, Rectangle) tiles it
```

Let the app's windows float while the reel plays. With yabai:

```sh
yabai -m rule --add label=demo app='^Musicbox$' manage=off
reel demo.reel
yabai -m rule --remove demo
```

If the app itself limits its window, ask for a size it allows.

## An element isn't found

`Click` and `Wait` look for `WaitTimeout` (10 s). A label must match exactly: a title, a description or a value.
Give the view an accessibility identifier and use `#identifier`; it survives copy changes and translations. An
element must be on a screen.

## reel render says an action changed

The reel's clicks, typing or keys no longer match the take. Record again with `reel demo.reel`. Captions, zooms on a
point, speed-ups, cuts and every output setting change without one: see [Making a demo](demos/index.md).

## A file is too big, or a render fails to fit

`Set MaxSize` fits a movie by lowering its bitrate, then its frame rate, then its width, in at most four encodes.
When even that is too big, the render fails and says the size it reached. Lower `VideoWidth` or `VideoFrameRate`, or
`Hide` the parts that don't need showing. For a GIF, lower `GifWidth` or `GifColors`. See
[Quality and size](outputs/quality-and-size.md).

## Narration lands in the wrong place

A marker's time is when the voice reaches it, measured when the line was voiced. Changing a line's text or voice
needs a new recording, so the reel is timed by the new line.

## A web page doesn't hover or scroll

WebKit, the default, gets no mouse moves or wheel events from a tool started in a terminal. Use
`Set Browser chromium`, which takes both.
