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
9. **Code screens.** `Screen code` instead of `Launch` or `Open`: reel's own editor (Monaco, shipped with reel) in a
   page nobody sees, drawn a frame at a time, with `Code`, `Go`, `Focus`, `Mark` and `Callout` (see "Code screens").
10. **Terminal screens.** `Screen terminal`: a real zsh in a pseudo-terminal of reel's own, drawn with xterm.js
   from what it printed and when, with `Wait /regex/`, `Wait quiet`, `Wait exit`, `Set Redact`, Ghostty themes and
   window chrome (see "Terminal screens").
11. **Scenes.** `Include[@<transition>] <scene.reel>`: other reels joined into one video, each recorded as its own,
   on one canvas, with transitions between them and the sequence's intro and outro around them (see "Scenes"). Still
   to come: a terminal width per profile (`Set Columns social ? 56 : 100`, one take per width).
12. **Between files.** `Code@<transition>`, `Split` and `Pane`, `Peek`, `Link` on a code screen (see "Code screens").
13. **Diffs.** `Diff <before> <after>`, `Diff <file> since <revision>`, `Go hunk <n>` (see "Code screens").
14. **Morph.** `Morph <file>`: the file shown turns into the next, word by word (see "Code screens").
15. **Reels together.** Phase 1: steps named `as <name>`; `Wait for <name> [to end]` across reels running at once,
   over a channel (see "Reels together"). Phase 2: code screens recorded as timed logs, reel scripts coloured.
   Phase 3: tracks, several subjects recorded at once in one reel (indented or `With x.reel as name`) and drawn
   together. Phase 4: `Follow`, a code screen marking the line of the reel it shows as that reel runs. Phase 5:
   `Attach`, an app something else opens, as a track. Phase 6: the director's moves (`Set Layout`, `Layout`,
   `Split`, `Spotlight`, `Fullscreen`, `Pip`). Next: the showcase; later, `Set Spotlight auto`.

## The reel

A reel is a `.reel` file (not `.tape`, which is VHS's, and which editors and GitHub would take for a VHS tape); any
other file is refused. One command per line. `#` starts a comment at the start of a line or followed by a space (`#play` after a command
is an identifier). A reel starts with `Launch <app>`, `Open <url>`, `Screen code`, `Screen terminal` or `Include <scene.reel>` (after any `Import` lines, see "Presets"), which says what it records; the rest is read
knowing it, so a setting for another kind (`Set Viewport` in an app reel, `Set Size` in a web reel, a `css:`
target in an app reel, `Click` on a code screen) is refused at its line rather than ignored. Setup (`Output`, `Set`, `Intro`, `Outro`) comes
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
| `Open <url>` | A web page to record instead of an app: `https://…`, `file://…` or an `.html` path, `#fragment` allowed. Later in the reel, goes to another page; a new fragment of the same page only scrolls, the same address reloads. |
| `Set Browser webkit\|chromium\|<app>` | WebKit, built in, is the default. `chromium` is any Chromium-based browser reel finds; an `.app` is that one. A chosen browser that cannot be had refuses the take; it never falls back. |
| `Set Viewport <w>x<h>` | The page's size in points, default 1280x800; a code screen's size too. |
| `Screen code` | A code screen to record instead of an app or a page: reel's own editor. See "Code screens". |
| `Set FontSize <points>` | A code screen's or a terminal's text, 8–72, default 18. |
| `Screen terminal` | A terminal to record instead: a real zsh in a terminal of reel's own. See "Terminal screens". |
| `Set Columns <n>`, `Set Rows <n>` | A terminal's size in characters, default 80 by 24; it sizes the screen. |
| `Set WorkingDirectory <path>`, `Set Title "<text>"`, `Set Theme <file.ghostty>` | Where the shell starts (the reel's folder), the window's title, the colours. |
| `Set Redact /<regex>/` | Cover what matches on a terminal's screen with dots, typed or printed; one per line. |
| `Include <scene.reel>`, `Include@<transition> <scene.reel>` | Join other reels into one video, as scenes. See "Scenes". |
| `Wait /<regex>/`, `Wait quiet [duration]`, `Wait exit` | On a terminal: until the output since the last input matches, until nothing is printed for a while (500ms), until the command ends. |
| `Code <file> [lines <a>-<b>] [at line <n> \| at "<text>"]` | Show a file (only lines `a`–`b`, numbered as in the file), the cursor at a line or the first text. |
| `Go line <n>`, `Go "<text>"` | Move the cursor there, the view easing to it when it is out of sight. |
| `Focus lines <a>-<b>`, `Focus off` | Dim every other line until `Focus off`. |
| `Mark "<text>" [n]`, `Mark off` | A box around the first text, numbered `n`; boxes add up until `Mark off`. |
| `Callout "<text>" "<label>"`, `Callout off` | A bubble saying the label beside the text's line, until the next callout or `Callout off`. |
| `Code@<transition> <file> …` | The file before moves out as the next comes in, with any intro transition; without one the file fades up. |
| `Split <file> […]`, `Split off`, `Pane left\|right` | A second pane, half the screen, which steps act on; `Pane` chooses which one does. |
| `Peek "<text>" <file> […]`, `Peek off` | Another file, up to 8 lines, in a box under the line with the text. |
| `Link "<a>" -> "<b>" ["<label>"]`, `Link off` | An arrow from one text to another, labelled, across the panes when split. |
| `Diff[@<transition>] <before> <after> [at …]`, `Diff <file> since <revision> [at …]` | Two versions of a file as one: kept, added and removed lines, changed words marked. |
| `Go hunk <n>`, `… at hunk <n>` | The first change of a diff's nth run of changes. |
| `Morph[@<easing>,<duration>] <file> […]` | The file shown turns into this one: shared words move, the rest fade; 900ms ease-in-out by default. |
| `Sleep <duration>` | Wait. |
| `Wait <element>` | Wait until the element shows. |
| `Click <element or @x,y>` | Glide the cursor there and click. |
| `Type "<text>"`, `Type@<duration> "<text>"` | Type the text, a character at a time; `\n` is return. |
| `Key <combo> [count]` | `return`, `a`, `cmd+s`, `ctrl+shift+tab`, `f5`; repeated `count` times. |
| `Scroll <up\|down\|left\|right> [lines] [element or @x,y]` | Scroll, over the element when one is named. |
| `Caption "<text>" [duration]`, `Caption off` | A caption from here until the next one, for `duration`, or until `Caption off`. |
| `Set KeyBadges on\|off` | A badge for each `Key` step (`⌘S`, `↓ ×3`), default on. |
| `Set ClickRipples on\|off` | A ripple where each click lands, default on. |
| `Set Cursor on\|off` | The cursor in the video, default on: a web reel's drawn one (render time), an app reel's real one (recording time). |
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
| `Say@<voice> "<text>"`, `Say@<voice>,over "<text>"` | Narrate in a voice named with `Set Voice <name> <voice>`. |
| `Wait [marker]` | Until the narration reaches a `[marker]` in the text of an earlier `Say@over`. |
| `Set Voice <voice>` | `system` (default), `system:Samantha`, or `voicebox:<profile name or id>`. |
| `Set Voice <name> <voice>` | Another voice, for `Say@<name>` lines: a second speaker. Letters, digits, `-` and `_`, not `over`. |
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
  (`GET /profiles`) and voices with `POST /generate/stream`, which answers WAV. A reel can have more than one:
  `Set Voice guest voicebox:Bella` names one, and `Say@guest` speaks in it; the seed, language and server are shared.
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
- **Open, later.** The driver asks the page where it is (`location.href`) and compares, as a browser does: another
  document loads, and waits for a new document (a flag set on the old one is gone) that is complete. The same
  document at a new `#fragment` is `location.assign`, which loads nothing, so waiting for a load hung for 15 s;
  it waits for the scroll to be still instead. The very same address reloads (`reload()`, `Page.reload`), so a page's
  animations start over: navigating there would only scroll to the fragment again.
- **Recording.** ScreenCaptureKit, as for an app, cropped to the page (`Recorder.pageCrop`), the browser's helper
  processes' sound kept. The crop never takes in a window's rounded corners, which would show the desktop behind
  them in an unframed output: WebKit's window is borderless (`PageWindow`, which says it can become key), so it is
  the page; Chromium's is sized until the page fills it, then grown `Browser.margin` (24 points) right and below,
  the page held at `Viewport` with `Emulation.setDeviceMetricsOverride`, which keeps it at the window's top left.
  Chromium's window rim, half a point, still shows along the page's left edge. `scripts/check-web.swift` checks the
  corners are the page's background. Neither takes the mouse or the keyboard, and neither needs Accessibility. The real cursor
  is hidden; render draws an arrow along the driver's path, through edits and zooms, unless `Set Cursor off`
  (`OverlayPlan.drawsCursor`). In an app reel `Set Cursor off` is `showsCursor = false` when capturing, so there it
  is fixed when recording and cannot differ by profile; a code or terminal screen refuses it (its caret is not the
  cursor).
- `mise run live-web` records `reels/web.reel` against `reels/web/fixture.html` twice, in WebKit and with `Set
  Browser chromium`: the page logs what happened (a `hashchange`, a reload) and the reel waits for each entry, so a
  step that did not work stops the take.

## Code screens

- **No app.** `Screen code` records reel's own editor: Monaco (`scripts/vendor-monaco.sh` pins it, 7.8 MB without
  its language services, which only an editing session needs) in a `WKWebView` that is never on screen. It needs no
  permission, no window, and nothing installed: the page, Monaco and the fonts ship beside reel in
  `Reel_ReelCore.bundle`, which reel finds next to its binary through Homebrew's symlink.
- **A clock of its own.** A code screen has nothing to capture in real time, so a take is drawn: the steps play on
  the take's own clock, and each frame is a snapshot of the page when its time comes. Nothing in the page reads the
  wall clock; `requestAnimationFrame` and every fade and scroll run when reel pumps the page, so the same reel draws
  the same take, and drawing it takes as long as it takes (about 12 ms a frame at 1280x720 points). A still screen
  writes no frames, as a capture of a still window sends none.
- **What it draws.** A header with the file's name, its folder from the git root, and its language (from Monaco's
  own list of extensions: Swift, TypeScript, JavaScript, JSON, YAML, Markdown, shell, Python, Rust, Go, C#, HTML, CSS,
  Java and more). The caret, marks and callouts are reel's own overlay, placed from Monaco's layout: Monaco draws its
  cursor only while focused, which a page nobody sees never is. A callout sits past the end of its line where it fits,
  so it covers no code. `Focus`, `Mark` and `Callout` are recorded with the take (a code screen's take is cheap to
  draw again), and the caret's path is the take's cursor, so `Zoom cursor` follows the typing.
- **Panes.** The page is one pane, or two after `Split`, each an editor with its own header, focus, marks and callout;
  steps act on the active one. `Code@<transition>` copies the pane's content into a layer over it that moves out as the
  new file comes in, so every intro transition works between files on reel's clock. `Peek` is a Monaco view zone (the
  public API) holding a second, read-only editor; it grows open, and the view scrolls ahead of it to where its bottom
  will be. `Link` is an SVG arrow over the panes, from the end of one text to the start of the other, drawing itself
  in; its label sits over the line numbers of the pane it points into, clear of code.
- **Diffs.** reel works them out itself (`CodeDiff`): the lines by Swift's `difference(from:)`, written out as a unified
  diff (removals before additions where they meet), then, where a removed and an added line in one place share at
  least 40% of their words, the words that changed. Monaco's own diff editor computes in a worker, which a page nobody
  sees does not run. The page shows the result in an ordinary pane with decorations; `Go line`, `Focus` and the line
  numbers use the new file's numbering. `since <revision>` reads the older version with `git show` when recording.
- **Morph** is drawn by reel over the editor. It measures every word the pane shows (text, place and colour, from
  Monaco's rendered lines), opens the next file and lays it out at once (`editor.render(true)`), and measures again.
  Lines that read the same are paired first, in order (the longest common run), so a moved line travels whole; the
  words of the lines left are paired in order, then any left over with the nearest of the same text. Copies of the
  words move on reel's clock while the real text is hidden, each corrected once for where a span sets its text against
  where Monaco does, and drawn without the font's ligatures as Monaco draws them, so the real text takes over at the
  end without a jump.
- **Keys.** `Type` and the keys an editor takes: return (keeping the line's indent), tab, space, backspace,
  forwarddelete, escape, the arrows, home, end, page up and down, with shift to select. Anything else is refused at
  its line.

## Terminal screens

- **A real shell.** `zsh -d -i` under `forkpty`, its home a temporary folder with a `.zshrc` of reel's: the folder and
  reel's chevron as the prompt, no history, no global rc files, and a `precmd` that prints OSC 133;D after every
  command, which is how `Wait exit` knows the prompt is back. Only `PATH`, `LANG` and a few basics come from the
  environment reel runs in. The commands are real, so a reel shows what is installed.
- **Two passes.** The shell runs in real time and every read is kept with its time (a character split across two
  reads waits for the rest); waits poll what was printed since the last input, without escape sequences, and after a
  return only what follows the command line: a command typed quickly can still be echoing when return is pressed. Then the
  terminal is drawn from that, as a code screen is: xterm.js (`scripts/vendor-xterm.sh` pins it) in a page nobody
  sees, fed each piece at its time, a frame snapshotted when its time comes. Drawing the same output twice gives the
  same frames; the shell's timing differs between takes, as an app's does.
- **What it draws.** A window: a bar with three dots and the title, then the terminal, sized from its columns and
  rows. xterm.js draws its cursor only once focused or typed into, so reel shows it itself. Marks and callouts find
  the last place their text shows, newest output first, and keep to that line of the buffer as the output scrolls.
- **Redaction** is drawn, not edited: the buffer keeps the real text, and every frame covers what a pattern matches
  on screen with dots, so a secret is covered from the first character that matches as it is typed. Editing the
  buffer instead leaked the rest of a typed secret, once its start no longer matched.
- **Patterns are one word.** The tokenizer reads `/…/` as one token, from a word's first `/` to the next unescaped
  `/` that ends a word, spaces, quotes and `#` kept as written; an `as` inside it is not a step's name. A word whose
  next slash does not end it (`/tmp/a.mp4`, `//docs/x`) is a word as before.
- **Size per profile** is not there yet: `Columns` is a recording setting, the same for every profile.

## Scenes

- **A reel of reels.** `Include` makes a reel a sequence: its scenes are other reels, each recorded into its own take
  next to its own reel (`Scenes.record`), and it has no steps and no recording settings of its own (a preset's pass
  by). `reel record` records every scene; `reel render` needs each scene's take and names a missing one. A reel of
  tracks is a scene too: it records with `Tracks.record`, and its take is the director's (`director.json`).
- **Render.** Each scene's demo is rendered as its own reel renders it (overlays, narration, cuts, zooms), read for
  the sequence's profile when the scene knows that name. Every scene is framed on one canvas: the Output's shape,
  16:9 without one, at the largest size any scene needs, so they line up. Then they are joined one after the other,
  each following scene coming in as an untitled video outro of what came before (`Assembler`), with its sound and
  its transition, and the sequence's intro and outro go around the whole. Outputs are written as for any reel. A
  reel of tracks has its tracks rendered once (`renderTrackDemos`), then, for each canvas, composed straight onto it
  (`composeTracks`, on the sequence's backdrop and padding) and its director's reel rendered over that, its intro and
  outro left out, as `renderTracks` does for the reel on its own. The canvas is framed and joined no wider than the
  widest Output of its shape is written (`Set VideoWidth`, `Set GifWidth`; `Scenes.workingSize`), at the size the
  movie would have been scaled to, so each pass handles no more pixels than are kept.
- **Not yet:** scenes written inline in one file, and narration that carries across a cut.

## Reels together

- **Names.** A trailing `as <name>` names any step; names are unique in a reel, and `as` on a line that is not a step
  is refused.
- **The channel** is a file of JSON lines, `{reel, line, name, phase: start|end, at}`, `at` in milliseconds since
  1970 so every process shares one clock. Every recorder appends a start and an end for each step it plays (one
  `write` with `O_APPEND`, which stays whole) and polls the file for `Wait for`. An event from before the wait counts:
  a step that has happened does not have to happen again. The path is `REEL_CHANNEL`; a terminal screen makes one in
  its take's folder (or uses the reel's own) and sets it for its shell.
- **Alone,** with no channel, a `Wait for` is skipped with a note, so every reel still records on its own. A wait on
  the reel's own step is refused at its line.
- **Tracks.** A `Launch`, `Open` or `Screen` line ending `as <name>`, with its indented lines, is a track: it is
  parsed as a reel of its own from the same text with every other line blank (its imports kept), so its errors name
  the file's lines. `With x.reel as name` reads one from a file. The unindented steps are the director's; a step that
  acts on a subject there is refused with where it belongs. Names are unique across the tracks and the director.
  `Speed` and `Hide`/`Show` are the director's only: a track is rendered alone and then lined up by its start, so a
  cut or speed-up in one track would put it out of step with the rest. In a track, indented or in a `With` file, they
  are refused at their line.
- **Recording tracks** (`Tracks.record`): every track and the director in one task group on one channel, the first
  to fail cancelling the rest. Each track records as its own reel does, into `.reel/<reel>/tracks/<name>/`, with
  `Take.startedAt`, the wall clock at its first frame. The channel knows which names the reel's own tracks take and
  who is waiting for what, so a deadlock among them stops at once; a wait for a name no track has may be answered from
  outside and waits its timeout. App steps take turns with the real mouse and keyboard (`InputTurns`).
- **Rendering tracks:** each track's demo is rendered as its reel would render it (overlays and zooms; it has no
  cuts), then a compositor
  (`TracksCompositor`) draws them all on one canvas per Output shape, each from its offset (`startedAt` against the
  director's), as windows on the backdrop, a track that has ended holding its last frame, the movie running as long
  as the director does. Where each is comes from `Direction`: a list of shots, each easing every track's placement
  (window, opacity, which is on top) from where it was at that moment to where the director's stage now puts it
  (`TrackLayout.placements`). A stage is the arrangement (`|` turned to `/` on a tall canvas), the split, the
  spotlight, a fullscreen or a picture-in-picture, and which tracks have started; the moves' times are their anchors
  in the director's take, and a track that starts more than half a second late is a change of its own. That movie is the director's take,
  rendered as any take: narration, captions, intro and outro. A background video is drawn as its first frame for now.
- **Attach.** A track whose subject is an app something else opens: it polls the running apps for its bundle id or
  path (at least a minute), then records the window as an app track does, posting its own name on the channel at the
  first frame, so others `Wait for` it. After its steps it holds until a `Stop` fires, once every other track and the
  director have finished (`Countdown`), or until the app quits.
- **Follow.** A watcher reads the channel while the track plays on, and for each step of the reel the pane shows
  (by file name) that starts, adds a call to the log that highlights its line, timed by the event's own wall clock
  against the take's start; a step that started before `Follow` shows from it. The log is shared with the watcher
  (`CallLog`) and drawn in time order. Another file in that pane, `Follow off`, or the track's end stops it.
- **Code screens** record in two passes, as terminals do: the steps play first, writing down each call to the page
  and when, then the page is drawn from that. Alone, the steps play on the take's own clock at once (a code reel
  records as fast as it draws); on a channel they keep real time, so what they say there lines up with the others.
  `.reel` and `.reelpreset` files are a language of their own in the editor: commands, quoted text, durations,
  `#identifiers`, `[markers]`, `as <name>`, conditions and comments each in their colour.

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
  cross the same way (through silence for a fade). The titles are drawn by Core Animation, which draws every frame
  of the movie, so a section with no title or subtitle (a sting, or the next scene of a sequence) leaves it out.
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
