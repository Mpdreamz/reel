# Plan

## Milestones

1. **Record a window with its sound.** The tape parser, `Launch`, `Sleep`, `Output` (`.mp4`, `.mov`) and `Set`;
   a take is the app's window and the app's audio captured with ScreenCaptureKit, plus a timeline; render exports
   it. `reel doctor`.
2. **Drive the app.** `Click`, `Type`, `Key`, `Wait`, `Scroll`, through Accessibility: elements by label or
   identifier, coordinates as the last resort. `Set Size` places the window. Clicks prefer `AXPress`, so a
   demo runs without taking focus.
3. **Overlays.** Captions, key badges and click ripples, drawn with Core Animation at render time and anchored to
   timeline events.
4. **GIF.** `Output demo.gif`, written with ImageIO from the rendered frames (no sound: a GIF has none).
5. **Zoom, speed and trim.** Zoom that follows the cursor, sped-up stretches, trimming to scenes.

## The tape (milestone 1)

One command per line; `#` starts a comment. Setup commands (`Output`, `Set`, `Launch`) come first, and recording
starts at the first command after them.

| Command | Meaning |
| --- | --- |
| `Output <path>` | A file to render: `.mp4` or `.mov`. Relative to the tape. At least one. |
| `Set FrameRate <n>` | Capture rate, 1–120, default 60. |
| `Set Audio on\|off` | Record the app's sound, default on. |
| `Launch <bundle id or .app path>` | The app to record. Exactly one. Reel waits for its first window. |
| `Sleep <duration>` | `500ms`, `2s`, `1.5s` or a bare number of seconds. |

## How a take is captured

- The filter is the app on its display (`SCContentFilter(display:including:)`), cropped to the window with
  `sourceRect`: menus, popovers and sheets are separate windows of the same app and still show; other apps do not.
- Audio is ScreenCaptureKit's own, scoped by the same filter to the app: no loopback driver.
- The take lives in `.reel/<tape name>/` next to the tape: `take.mov` (H.264 and AAC) and `take.json` (size, scale,
  and when each command ran, in milliseconds from the first frame).

## Prior art

[deskagent](https://github.com/MobAI-App/deskagent) and
[desktop-recorder-skill](https://github.com/MobAI-App/desktop-recorder-skill) (both MIT) record scripted macOS demos
with a JSON screenplay. Ideas taken from them: overlays anchored to timeline events rather than seconds, `AXPress`
for clicks on an app that is not frontmost, and a `doctor` command. They capture no audio and write no GIFs, and
their editing runs through Node and ffmpeg.
