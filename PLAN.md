# Plan

## Milestones

1. **Record a window with its sound.** The reel parser, `Launch`, `Sleep`, `Output` (`.mp4`, `.mov`) and `Set`;
   a take is the app's window and the app's audio captured with ScreenCaptureKit, plus a timeline; render exports
   it. `reel doctor`.
2. **Drive the app.** `Click`, `Type`, `Key`, `Wait`, `Scroll` and `Set Size`, through Accessibility: elements by
   label or identifier, points as the last resort. Input is real (see "How a reel drives the app").
3. **Overlays.** Captions, key badges and click ripples, drawn with Core Animation at render time from the
   timeline (see "Overlays").
4. **GIF.** `Output demo.gif`, sampled from the rendered movie and written with ImageIO (see "GIFs").
5. **Narration.** `Say` lines voiced by macOS or a voicebox server, the reel timed by them, mixed in with the
   app's sound ducked under them (see "Narration").
6. **Zoom, speed and trim.** `Zoom` on an element (locked and followed), a point or the cursor; `Speed` up
   stretches, narration kept at its pace; `Hide` … `Show` cuts (see "Zoom, speed and trim").
7. **Intro and outro.** Title cards before and after the demo, over a colour, an image or a video (its sound kept),
   with transitions into and out of the demo (see "Intro and outro").
8. **Web pages.** `Open <url>` instead of `Launch`: in WebKit by default, or a Chromium-based browser over DevTools,
   only the page recorded, with a drawn cursor (see "Web pages"). macOS only, reels only; Playwright journeys and other
   platforms are still to be discussed.

## The reel

A reel is a `.reel` file (not `.tape`, which is VHS's, and which editors and GitHub would take for a VHS tape); any
other file is refused. One command per line. `#` starts a comment at the start of a line or followed by a space (`#play` after a command
is an identifier). A reel starts with `Launch <app>` or `Open <url>` (after any `Import` lines, see "Presets"), which says what it records; the rest is read
knowing it, so a setting for the other kind (`Set Viewport` in an app reel, `Set Size` in a web reel, a `css:`
target in an app reel) is refused at its line rather than ignored. Setup (`Output`, `Set`, `Intro`, `Outro`) comes
next, and recording starts at the first command after it. Durations are `500ms`, `2s`, `1.5s`, `1m` or a bare number of seconds.

A path is relative to the file it is written in, from home with `~`, absolute with `/`, or from the git root with
`//` (`Output //docs/media/demo.mp4`), so a reel or a preset need not count `../`; `//` outside a git repository is
an error. A relative path that leads out of the git root plays, with a warning: it works only where the repository
sits next to the same things.

| Command | Meaning |
| --- | --- |
| `Output <path>` | A file to render: `.mp4`, `.mov` or `.gif` (no sound). Relative to the reel. At least one. |
| `Output@<shape> <path>` | The recording framed on a canvas: an aspect (`@16:9`, `@1:1`, `@9:16`) or an exact size (`@1080x1080`). |
| `Set Background <bg>` | Frame the recording on a backdrop in every output: `#rrggbb`, an image, or a video (looped, silent). |
| `Set Padding <n%>` | Room around a framed recording, a share of the canvas's shorter side; default 6%, up to 30%. |
| `Set FrameRate <n>` | Capture rate, 1–120, default 60. |
| `Set Audio on\|off` | Record the app's sound, default on. |
| `Set Size <w>x<h>` | The window's size in points, before recording. |
| `Set TypingSpeed <duration>` | The pause after each typed character, default 50ms. |
| `Set WaitTimeout <duration>` | How long `Wait` and `Click` look for an element, default 10s. |
| `Launch <bundle id or .app path>` | The app to record: a bundle id, or a path with a slash (`./Name.app` beside the reel). Reel waits for its first window. |
| `Open <url>` | A web page to record instead of an app: `https://…`, `file://…` or an `.html` path. Later in the reel, goes to another page. |
| `Set Browser webkit\|chromium\|<app>` | WebKit, built in, is the default. `chromium` is any Chromium-based browser reel finds; an `.app` is that one. A chosen browser that cannot be had refuses the take; it never falls back. |
| `Set Viewport <w>x<h>` | The page's size in points, default 1280x800. |
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
| `Set GifColors <n>` | Colours in a GIF, 2–256, default 256. Fewer make a smaller file; one palette serves every frame. |
| `Set Quality <n>` | How a movie is compressed, 1–100, default 65: a fraction of the size of the best, since screen recordings are mostly still. |
| `Set Codec h264\|hevc\|prores` | A movie's codec, default `h264`, which plays everywhere; `hevc` is about half the size and plays on Apple devices and in most current browsers; `prores` is lossless for editing, in a `.mov` (an `.mp4` gets H.264 at quality 100). |
| `Set VideoWidth <pixels>` | Scale movies down to this width, 100–8000, never up; default the full Retina size. |
| `Set VideoFrameRate <n>` | Frames a second in a movie, at most the recording's; default the recording's. |
| `Set MaxSize <size>` | The most an Output may be: `10MB`, `500KB`, `1.5GB` (thousands, as sites count). See "Fitting a size". |
| `Set MaxLength <duration>` | The longest an Output may run; a longer one fails the render. |
| `Set Shape <shape>` | Frame every Output that names no shape of its own (`Output@…`): `16:9`, `1080x1920`. |
| `Set Formats <types>` | Write only these types of Output, `mp4, mov`; the others are skipped with a note. |
| `Set Profiles <names>` | Render every Output once for each profile, as `name-<profile>.mp4`. See "Profiles". |
| `Say "<text>"`, `Say@over "<text>"` | Narrate; blocks until the line ends, or with `@over` carries on while it plays. |
| `Wait [marker]` | Until the narration reaches a `[marker]` in the text of an earlier `Say@over`. |
| `Set Voice <voice>` | `system` (default), `system:Samantha`, or `voicebox:<profile name or id>`. |
| `Set VoiceServer <url>` | voicebox's address, default `http://127.0.0.1:17493`. |
| `Set VoiceSeed <n>`, `Set VoiceLanguage <xx>` | voicebox's seed (default 1) and language (default `en`). |
| `Set Ducking <n%>` | The app's sound under narration, default 25%. |
| `Set VoiceVolume <n%>`, `Set AppVolume <n%>` | Levels in the mix, default 100%. |
| `Set Subtitles on\|off` | Show each `Say` as a caption while it plays, default off. |
| `Zoom <element> [scale]` | Zoom onto an element and stay locked on it, following it, until the next `Zoom`. Fitted with room when no scale, at most 4×. |
| `Zoom @x,y [scale]`, `Zoom cursor [scale]` | Zoom on a point, or follow the cursor; default 2×. |
| `Zoom off` | Back to the whole window. |
| `Zoom@<easing>,<duration> …` | Any zoom with its own move: `Zoom@ease-out #list`, `Zoom@600ms off`, `Zoom@smooth,1s cursor`. |
| `Intro "<title>" ["<subtitle>"] [duration]` | A title card before the demo; 3 s, or a background video's own length. |
| `Outro "<title>" ["<subtitle>"] [duration]` | One after it. |
| `Intro [duration]`, `Outro [duration]` | No title: the background video on its own, such as a designed sting. Needs a video background (`Set IntroBackground`, `Set OutroBackground`). |
| `Intro@<kind>,<easing>,<duration> …` | How the intro moves into the demo (an outro: how the demo moves into it): `crossfade` (default, 600ms), `fade` (through black), `slide-left`/`-right`/`-up`/`-down`, `zoom`, `wipe-left`/`-right`/`-up`/`-down`, `cut`; any easing. |
| `Set IntroBackground <bg>`, `Set OutroBackground <bg>` | `#rrggbb`, an image (`.png`, `.jpg`, `.heic`) or a video (`.mov`, `.mp4`), whose sound plays with it; default a near-black. |
| `Set ZoomEasing <easing>`, `Set ZoomDuration <duration>` | How zooms move when they say nothing: `linear`, `ease-in`, `ease-out`, `ease-in-out` (default), `smooth` or `snap`; 400ms by default. |
| `Speed <rate>x` … `Speed off` | Play the stretch faster (above 1× to 16×); narrated lines keep their own pace, the app's sound is left out. |
| `Hide` … `Show` | Leave the stretch out of the render; a `Hide` with no `Show` runs to the end. |

An element is `"Label"` (its title, description or value, exactly; quoted is always a label), `#identifier` (its
accessibility identifier) or a bare word as a label. `@x,y` is points from the window's top left. Elements are found
breadth first across the app's windows, so sheets and popovers count, and must be on a screen.

## How a reel drives the app

- **Real input, not `AXPress`.** The cursor glides to what it clicks and the click is a real one; keys are real key
  presses, text is typed a character at a time. A demo is meant to show a person using the app, and an `AXPress`
  click shows a button reacting with no cursor near it. The cost: the reel takes the mouse and keyboard while it
  plays.
- **Never into another app.** Before every input step the driver checks the app is frontmost, brings it back once,
  and otherwise stops the reel, so typing cannot land in the terminal.
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
  on its own, and cached in `.reel/<reel>/voice/` by text, voice and seed. A marker's time is the length of the
  pieces before it, exactly; no alignment or speech recognition. The cost is a seam in intonation at each marker.
- **The reel runs on a speech clock.** `Say` blocks for its line's length; `Say@over` starts it and carries on;
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

## Zoom, speed and trim

- **Render-time edits, anchored like captions.** `Speed`, `Hide`/`Show` and zooms on a point or the cursor take
  effect at the end of the action before them and change without a new take. A zoom on an element is an action:
  recording finds the element, keeps its frame in the timeline, and reads it again after every step while the zoom
  holds, so render follows it if it moves. Changing it needs a new take.
- **Zoom** is a transform on the picture, sampled 30 times a second into transform ramps, each move eased by its
  `Zoom@` option or the reel's `ZoomEasing` and `ZoomDuration` (ease-in-out over 0.4 s unless set): cubic `ease-in`,
  `ease-out` and `ease-in-out`, `linear`, `smooth` (half a sine) or `snap` (no move). An element zoom's timeline
  names the element alone, so its scale and easing change without a new take. The
  region keeps the window's shape and stays inside it. A fitted element gets 8% room and at most 4×; render says so
  when an element nearly fills the window and fitting it barely zooms. Captions and badges are drawn after the zoom,
  so they stay put; a ripple is moved to where its click shows under the zoom.
- **The cursor** is sampled about 30 times a second through every take (`Take.cursor`); `Zoom cursor` follows it
  averaged over 0.3 s, so the zoom glides rather than jitters.
- **Time.** The edit (`.reel/<reel>/edit.json`) lists what is kept of the take and how fast; everything timed
  (overlays, narration, ducking, zoom) is mapped through it. A sped-up stretch carries no app sound; narration is
  never sped up, and a `Hide` that would cut a narrated line is refused.

## Web pages

- **Which browser.** WebKit, built into macOS, unless the reel says otherwise: nothing to install. `Set Browser
  chromium` is the first installed of Chrome, Chromium, Brave and Edge, else the newest Chromium Playwright
  downloaded (`~/Library/Caches/ms-playwright/chromium-<build>`); `Set Browser <path>.app` is that browser. A chosen
  browser that is not there refuses the take rather than fall back. `reel doctor` says what `chromium` would be.
- **One driver, two pages.** The web driver finds elements with the same JavaScript in both and keeps the drawn
  cursor's path; a `Page` does the input. Elements: `"Label"` matches an element's accessible name, placeholder,
  title, alt, button value or text exactly, controls before other elements, then the smallest; `#id` an id or
  `data-testid`; `css:<selector>` the first visible match (quoted after the colon when it has spaces: `css:"form button"`). A click scrolls its element into the middle first.
- **WebKit** is a `WKWebView` in a window of reel's own (reel shows a Dock icon while it is up). Clicks and keys are
  AppKit events sent straight to the view, which the page sees as trusted. macOS editing shortcuts are the view's own
  actions (selectAll:, copy:, …). Its gaps, because WebKit takes mouse moves and wheel events only while its app is
  active, which a tool started from a terminal cannot make itself: no hover (the page sees no mouse moves), scrolling
  is the page scrolling its nearest scrollable element under the cursor (scroll events fire; wheel events do not),
  and no focus ring. Pages render as in Safari. A page's sound plays in WebKit's helper processes, which Safari's own
  pages share: sound Safari plays during a take is recorded too.
- **Chromium** is a browser reel starts as an app window (no tabs, no address bar) on a fresh, temporary profile
  with a DevTools port (`--remote-debugging-port=0`, read from `DevToolsActivePort`), sized until the page is
  `Viewport`, quit and its profile removed when the take ends. Input is DevTools' (`Input.dispatchMouseEvent`,
  `dispatchKeyEvent`): hovers and wheel events included. Editing shortcuts are sent as the commands DevTools needs.
- **Recording.** ScreenCaptureKit, as for an app, cropped to the page under the title bar, the browser's helper
  processes' sound kept. Neither takes the mouse or the keyboard, and neither needs Accessibility. The real cursor
  is hidden; render draws an arrow along the driver's path, through edits and zooms.
- `mise run live-web` records `reels/web.reel` against `reels/web/fixture.html` twice, in WebKit and with `Set
  Browser chromium`: the page logs what happened and the reel waits for each entry, so a step that did not work stops
  the take.

## Framing

- **What it is.** An output with a shape (`Output@1:1 …`), or every output once `Set Background` is set, shows the
  recording on a canvas: the recording centred with `Padding` around it, rounded corners (12 points, scaled) and a
  soft shadow, over the background. Outputs without either are the bare recording, as before.
- **Sizes.** An aspect gets the smallest canvas that holds the recording at its own size with the padding, at most
  3840 pixels on its longer side (a 2560×1600 recording: 1:1 is 2908², 16:9 is 3232×1818, 9:16 is 2160×3840); an exact
  size fits the recording in. Every size is even, as H.264 wants.
- **How.** A pass after the demo is rendered (losslessly): a custom compositor (`FrameCompositor`) draws each frame
  with Core Image. A video background is looped to the demo's length and adds no sound. An intro and an outro are
  assembled around the framed demo, so they fill the whole canvas. A GIF is made from the movie Output with the same
  framing, or a temporary one.

## Intro and outro

- **A second pass.** With an intro or an outro, the demo is rendered once, losslessly (ProRes and PCM), to
  `.reel/<reel>/demo.mov`, and each output is assembled from it: the intro, the demo and the outro on one timeline,
  each on its own track. A colour or image background becomes a still clip of the section's length; a video fills the
  frame (cropped evenly) and keeps its sound. `sections.json` says where the demo starts in the finished movie.
- **Transitions are one function.** For each moment of a transition, `Look.of` gives each section's opacity, offset,
  scale and crop; the assembler samples it 30 times a second into the video's opacity, transform and crop ramps, and
  into keyframes for the titles, so a title moves (or is wiped) with its section. The intro and the outro are drawn
  over the demo: crossfades, zooms and wipes work on them and reveal the demo beneath; slides push both. A fade goes
  through black across the cut, half on either side; the others overlap the two sections for their length. Sounds
  cross the same way (through silence for a fade).
- **Render-time only**, like captions: a changed title, background or transition needs no new take.

## GIFs

- **From the rendered movie**, overlays included: the reel's first `.mp4` or `.mov` Output, or a temporary
  `rendered.mov` in the take's directory when it has none. Frames are sampled at `GifFrameRate` and scaled to
  `GifWidth`, then written by ImageIO, looping forever.
- **Still stretches are one frame.** A frame that looks the same as the one being held (every channel within 16
  of 255) extends it: a still window decodes with compression noise up to about 13, a real change moves channels by
  100 or more. On the fixture, 57 of 80 sampled frames are kept; a calmer demo merges more.
- **Timing does not drift.** GIF delays are hundredths of a second; each frame runs from its start, rounded, to the
  next one's, rounded, so 15 frames a second alternate 7 and 6 and add up exactly.

## Profiles

A profile is a named set of render settings for where a video is going. `Set Profiles github, social` renders every
Output once for each, as `musicbox-github.mp4` and `musicbox-social.mp4`, from the one take; the suffix is there
whenever a profile is, so a file's name never depends on how many were rendered. A profile's settings apply after
the reel's own, so a plain `Set` never cancels one. `--profile` on `run`, `render` and `check` renders only some
(repeated, or `github,social`): from among the reel's when it lists any, from all of them when it does not. An
unknown name, or one the reel does not list, is refused before anything is recorded. `reel profiles` lists them:

| Profile | For | Sets |
|---|---|---|
| `highest` | archiving, editing later | `Codec prores` (a `.mov` is ProRes 422, an `.mp4` H.264 at quality 100), GIFs full width at 30 fps |
| `github` | READMEs, issues, pull requests | 1920 wide, `MaxSize 10MB` (GitHub's limit for an attached video or GIF), GIFs 800 wide |
| `web` | landing pages, docs sites | 1920 wide, quality 60, 30 fps |
| `social` | YouTube Shorts, TikTok, Reels | `1080x1920`, quality 70, 30 fps, `MaxSize 250MB`, `MaxLength 3m`, subtitles on, no GIFs |
| `feed` | X, Bluesky, Mastodon, LinkedIn | `1920x1080`, 30 fps, `MaxSize 40MB`, `MaxLength 140s`, subtitles on, no GIFs |
| `square` | Instagram and LinkedIn feeds | `1080x1080`, 30 fps, `MaxSize 40MB`, `MaxLength 140s`, subtitles on, no GIFs |

The social limits are the strictest common ones, from third-party guides where the platform publishes none
(Mastodon's 40 MB default, X's 2:20 for standard accounts, TikTok's 287 MB on mobile). Subtitles are on because
feeds play muted. A landscape app framed at 9:16 is mostly background: `Zoom` is what makes a vertical cut work.

### Presets

Settings and profiles a team shares live in a `.reelpreset`, which reels import on their first lines, before
`Launch` or `Open` (comments may come before):

```
Import //demos/house.reelpreset
Launch ~/Projects/musicbox/build/App/Musicbox.app
```

A preset holds `Import` lines (first; presets import presets, in order, and one that comes back round is an error),
`Set` lines and `Profile` blocks, and nothing that records. Its `Set` lines are defaults: they apply as the reel says
what it records, before the reel's own, which override them; a profile overrides both. A path in a preset is
relative to the preset. An error in one names the file and line.

```
# house.reelpreset
Set Background //design/backdrop.png
Set Voice system:Samantha

Profile github                     # amends the built-in github: its settings after github's own
  Set GifColors 128

Profile docs extends web "Our docs site"
  Set VideoWidth 1440
  Set MaxSize 8MB
```

`Profile <name> [extends <profile>] ["what it is for"]` and the indented `Set` lines under it define a profile, in a
preset or in a reel; the block ends at the first line that is not indented. A known name amends that profile; a new
one starts from the profile it extends, or from nothing. Names are lowercase letters, digits and dashes, and not an
Output's type (`mp4`, `mov`, `gif`). A profile cannot set what is fixed when recording (`FrameRate`, `Audio`, `Size`,
`TypingSpeed`, `WaitTimeout`, the `Voice` settings, `Browser`, `Viewport`), since one take serves every profile, nor
choose profiles. `reel profiles demo.reel` lists what a reel can render for, with where each setting comes from;
`reel run` reads every profile it will render before recording, so a bad value is refused first.

### Conditions

A value may differ by profile: `Set Quality social|feed ? 70 : github ? 50 : 65`. Conditions are read left to
right; the first that holds chooses its value, and the last value is for when none does, or no profile renders. A
condition is a profile's name, or names joined by `|`; it may also be an Output's type, `mp4`, `mov` or `gif`, and
then each type is rendered from its own reading (`Caption gif ? "Short" : "The long version"`). One profile renders
at a time, so a condition inside a chosen value could never matter: it is refused, and a chain is all there is. A
line that starts with `:` continues the one before it, so a long chain lines up:

```
Caption github ? "brew install --cask mpdreamz/tap/reel"
        : social|feed ? "Follow for more"
        : "Recorded with reel"
```

Conditions work where render decides: `Set` (but not the settings fixed when recording, nor `Profiles`), `Caption`,
`Intro` and `Outro`, in a reel, a preset or a profile. A condition covers all of a command's values (`Outro social ?
"Title" "Subtitle" : "Title" "Other subtitle"`). Anything that happens while recording (`Say`, `Type`, `Click` and
the rest) is the same for every profile, since one take serves them all; a condition there is refused. A name a
condition tests must be a known profile or a type.

### Fitting a size

A movie is encoded at its quality first. Over `MaxSize`, it is encoded again at the bitrate the size leaves for its
length (less the sound's), and each later try aims through the last two, since a busy picture has a floor its size
will not go under; one that lands well under is tried once more, richer. When the bitrate would be too lean for the
picture, it drops to 30 frames a second, then narrows. At most four encodes; then the render fails, naming the size
it reached and what to lower, and leaves no file. A GIF over its size is drawn again with fewer colours (128, then
64), then fewer frames (10 a second), then narrower, all at once when it is far over; at most six writes.

## How a take is captured

- The filter is the window's display without every other running app (`excludingApplications:`), cropped to the
  window with `sourceRect`: menus, popovers and sheets are separate windows of the same app and still show; other
  apps do not. Scoping it with `including: [app]` instead makes macOS draw a sharing indicator over the window's
  buttons, so the take would show it.
- Audio is ScreenCaptureKit's own, scoped by the same filter to the app: no loopback driver.
- Known gaps: the window's rounded corners show what is behind them (the wallpaper), the window keeps the size and
  place it opened with, and an app that starts after the first frame is not excluded.
- The take lives in `.reel/<reel name>/` next to the reel: `take.mov` (H.264 and AAC) and `take.json` (size, scale,
  and when each command ran, in milliseconds from the first frame).

## Prior art

[deskagent](https://github.com/MobAI-App/deskagent) and
[desktop-recorder-skill](https://github.com/MobAI-App/desktop-recorder-skill) (both MIT) record scripted macOS demos
with a JSON screenplay. Ideas taken from them: overlays anchored to timeline events rather than seconds, `AXPress`
for clicks on an app that is not frontmost, and a `doctor` command. They capture no audio and write no GIFs, and
their editing runs through Node and ffmpeg.
