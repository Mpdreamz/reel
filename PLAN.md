# Plan

## Milestones

1. **Record a window with its sound.** The tape parser, `Launch`, `Sleep`, `Output` (`.mp4`, `.mov`) and `Set`;
   a take is the app's window and the app's audio captured with ScreenCaptureKit, plus a timeline; render exports
   it. `reel doctor`.
2. **Drive the app.** `Click`, `Type`, `Key`, `Wait`, `Scroll` and `Set Size`, through Accessibility: elements by
   label or identifier, points as the last resort. Input is real (see "How a tape drives the app").
3. **Overlays.** Captions, key badges and click ripples, drawn with Core Animation at render time from the
   timeline (see "Overlays").
4. **GIF.** `Output demo.gif`, sampled from the rendered movie and written with ImageIO (see "GIFs").
5. **Narration.** `Say` lines voiced by macOS or a voicebox server, the tape timed by them, mixed in with the
   app's sound ducked under them (see "Narration").
6. **Zoom, speed and trim.** Zoom that follows the cursor, sped-up stretches, trimming to scenes. Speed-ups skip
   narrated stretches: sped-up speech is no use.

## The tape

One command per line. `#` starts a comment at the start of a line or followed by a space (`#play` after a command
is an identifier). Setup commands (`Output`, `Set`, `Launch`) come first, and recording starts at the first command
after them. Durations are `500ms`, `2s`, `1.5s`, `1m` or a bare number of seconds.

| Command | Meaning |
| --- | --- |
| `Output <path>` | A file to render: `.mp4`, `.mov` or `.gif` (no sound). Relative to the tape. At least one. |
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
| `Set GifFrameRate <n>` | Frames a second in a GIF, 1–50, default 15. |
| `Set GifWidth <pixels>` | A GIF's width, 100–4000, default 800, never wider than the video. |
| `Say "<text>"`, `Say@over "<text>"` | Narrate; blocks until the line ends, or with `@over` carries on while it plays. |
| `Wait [marker]` | Until the narration reaches a `[marker]` in the text of an earlier `Say@over`. |
| `Set Voice <voice>` | `system` (default), `system:Samantha`, or `voicebox:<profile name or id>`. |
| `Set VoiceServer <url>` | voicebox's address, default `http://127.0.0.1:17493`. |
| `Set VoiceSeed <n>`, `Set VoiceLanguage <xx>` | voicebox's seed (default 1) and language (default `en`). |
| `Set Ducking <n%>` | The app's sound under narration, default 25%. |
| `Set VoiceVolume <n%>`, `Set AppVolume <n%>` | Levels in the mix, default 100%. |
| `Set Subtitles on\|off` | Show each `Say` as a caption while it plays, default off. |

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

## Narration

- **Voiced before recording.** Every `Say` is voiced before the app opens, each piece of text between `[markers]`
  on its own, and cached in `.reel/<tape>/voice/` by text, voice and seed. A marker's time is the length of the
  pieces before it, exactly; no alignment or speech recognition. The cost is a seam in intonation at each marker.
- **The tape runs on a speech clock.** `Say` blocks for its line's length; `Say@over` starts it and carries on;
  `Wait [marker]` sleeps until the line reaches the marker. Lines never overlap: one starts when the line before
  ends. The take runs until the last line has been said. Nothing is played aloud while recording.
- **Mixed at render time.** Each line is placed where the take recorded it, the app's sound ramps (0.2 s) down to
  `Ducking` under it, lines close together duck as one. Render never voices a line: voiced again it may come out a
  different length, and the take was timed to the first; a line whose text, voice or seed changed needs a new take.
- **Voices.** macOS's own synthesizer needs nothing and works offline; voicebox
  (https://github.com/jamiepine/voicebox, MIT) runs locally: reel looks the profile up by name or id
  (`GET /profiles`) and voices with `POST /generate/stream`, which answers WAV.
- **Subtitles** take the caption's place: a `Caption` showing during a line is cut around it. A GIF has no sound,
  so subtitles are how narration reaches one.

## GIFs

- **From the rendered movie**, overlays included: the tape's first `.mp4` or `.mov` Output, or a temporary
  `rendered.mov` in the take's directory when it has none. Frames are sampled at `GifFrameRate` and scaled to
  `GifWidth`, then written by ImageIO, looping forever.
- **Still stretches are one frame.** A frame that looks the same as the one being held (every channel within 16
  of 255) extends it: a still window decodes with compression noise up to about 13, a real change moves channels by
  100 or more. On the fixture, 57 of 80 sampled frames are kept; a calmer demo merges more.
- **Timing does not drift.** GIF delays are hundredths of a second; each frame runs from its start, rounded, to the
  next one's, rounded, so 15 frames a second alternate 7 and 6 and add up exactly.

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
