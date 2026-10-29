# Plan

## Milestones

1. **Record a window with its sound.** The tape parser, `Launch`, `Sleep`, `Output` (`.mp4`, `.mov`) and `Set`;
   a take is the app's window and the app's audio captured with ScreenCaptureKit, plus a timeline; render exports
   it. `reel doctor`.
2. **Drive the app.** `Click`, `Type`, `Key`, `Wait`, `Scroll` and `Set Size`, through Accessibility: elements by
   label or identifier, points as the last resort. Input is real (see "How a tape drives the app").
3. **Overlays.** Captions, key badges and click ripples, drawn with Core Animation at render time from the
   timeline (see "Overlays").
4. **GIF.** `Output demo.gif`, written with ImageIO from the rendered frames (no sound: a GIF has none).
5. **Zoom, speed and trim.** Zoom that follows the cursor, sped-up stretches, trimming to scenes.

## The tape

One command per line. `#` starts a comment at the start of a line or followed by a space (`#play` after a command
is an identifier). Setup commands (`Output`, `Set`, `Launch`) come first, and recording starts at the first command
after them. Durations are `500ms`, `2s`, `1.5s`, `1m` or a bare number of seconds.

| Command | Meaning |
| --- | --- |
| `Output <path>` | A file to render: `.mp4` or `.mov`. Relative to the tape. At least one. |
| `Set FrameRate <n>` | Capture rate, 1–120, default 60. |
| `Set Audio on\|off` | Record the app's sound, default on. |
| `Set Size <w>x<h>` | The window's size in points, before recording. |
| `Set TypingSpeed <duration>` | The pause after each typed character, default 50ms. |
| `Set WaitTimeout <duration>` | How long `Wait` and `Click` look for an element, default 10s. |
| `Launch <bundle id or .app path>` | The app to record. Exactly one. Reel waits for its first window. |
| `Sleep <duration>` | Wait. |
| `Wait <element>` | Wait until the element shows. |
| `Click <element or @x,y>` | Glide the cursor there and click. |
| `Type "<text>"`, `Type@<duration> "<text>"` | Type the text, a character at a time; `\n` is return. |
| `Key <combo> [count]` | `return`, `a`, `cmd+s`, `ctrl+shift+tab`, `f5`; repeated `count` times. |
| `Scroll <up\|down\|left\|right> [lines] [element or @x,y]` | Scroll, over the element when one is named. |
| `Caption "<text>" [duration]`, `Caption off` | A caption from here until the next one, for `duration`, or until `Caption off`. |
| `Set KeyBadges on\|off` | A badge for each `Key` step (`⌘S`, `↓ ×3`), default on. |
| `Set ClickRipples on\|off` | A ripple where each click lands, default on. |

An element is `"Label"` (its title, description or value, exactly; quoted is always a label), `#identifier` (its
accessibility identifier) or a bare word as a label. `@x,y` is points from the window's top left. Elements are found
breadth first across the app's windows, so sheets and popovers count, and must be on a screen.

## How a tape drives the app

- **Real input, not `AXPress`.** The cursor glides to what it clicks and the click is a real one; keys are real key
  presses, text is typed a character at a time. A demo is meant to show a person using the app, and an `AXPress`
  click shows a button reacting with no cursor near it. The cost: the tape takes the mouse and keyboard while it
  plays.
- **Never into another app.** Before every input step the driver checks the app is frontmost, brings it back once,
  and otherwise stops the tape, so typing cannot land in the terminal.
- **Window managers.** A tiling window manager (yabai, Rectangle) resizes the window after `Set Size`; reel reads
  the size back and warns. `scripts/live.sh` floats the fixture with a yabai rule that only lives while it runs.
- **Timeline.** Each step's event records when it ran and, for a click, where it landed in window points: what
  milestone 3's click ripples need.

## Overlays

- **Captions are not recorded.** Recording skips them; render anchors each one to the end of the action before it in
  the take's timeline. Captions can be added, moved, reworded or removed and rendered again without a new take; an
  action that changed since the take (render compares each action's line with the timeline) needs one.
- **Key badges and ripples come from the timeline**: a badge from a `Key` step's start until 0.6 s after it, a
  ripple from the press of a click (its point is in the timeline) for 0.5 s.
- **Drawn by Core Animation** through `AVVideoCompositionCoreAnimationTool` during the export, sized from the
  video. Text is drawn into an image first: a `CATextLayer` draws nothing when AVFoundation renders off screen.
  Animations fill forwards only, since filling backwards would show each overlay's first frame from the start.

## How a take is captured

- The filter is the window's display without every other running app (`excludingApplications:`), cropped to the
  window with `sourceRect`: menus, popovers and sheets are separate windows of the same app and still show; other
  apps do not. Scoping it with `including: [app]` instead makes macOS draw a sharing indicator over the window's
  buttons, so the take would show it.
- Audio is ScreenCaptureKit's own, scoped by the same filter to the app: no loopback driver.
- Known gaps: the window's rounded corners show what is behind them (the wallpaper), the window keeps the size and
  place it opened with, and an app that starts after the first frame is not excluded.
- The take lives in `.reel/<tape name>/` next to the tape: `take.mov` (H.264 and AAC) and `take.json` (size, scale,
  and when each command ran, in milliseconds from the first frame).

## Prior art

[deskagent](https://github.com/MobAI-App/deskagent) and
[desktop-recorder-skill](https://github.com/MobAI-App/desktop-recorder-skill) (both MIT) record scripted macOS demos
with a JSON screenplay. Ideas taken from them: overlays anchored to timeline events rather than seconds, `AXPress`
for clicks on an app that is not frontmost, and a `doctor` command. They capture no audio and write no GIFs, and
their editing runs through Node and ffmpeg.
