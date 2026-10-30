# reel

Record demos of macOS apps from a script. Like [VHS](https://github.com/charmbracelet/vhs), but for windows instead
of terminals, and with the app's sound.

```
# demo.reel
Launch com.example.musicbox

Output demo.mp4
Output demo.gif
Set Size 1280x800

Set Voice voicebox:narrator      # or system, macOS's own voice
Intro@slide-up,ease-out "Musicbox" "A music player for your Mac"
Outro@fade "Get it" "brew install --cask musicbox"
Set IntroBackground media/intro.mov   # or #1d2b3a, or an image; a video keeps its sound

Hide
Wait "Library"
Show
Say "This is Musicbox."
Zoom #library                    # locks on the library, and follows it
Say@over "Pick a track, [pick] then press [play] space to play it."
Wait [pick]
Click "Midnight City"
Wait [play]
Key space
Zoom off
Sleep 4s
```

```sh
reel check demo.reel    # parse it and say what it would do
reel demo.reel          # record, then render every Output
reel record demo.reel   # only capture the take (.reel/demo/)
reel render demo.reel   # only render the outputs from the last take
reel doctor             # Screen Recording, Accessibility, and the browser web tapes use
```

Status: milestones 1 to 8 of [PLAN.md](PLAN.md): recording a window with its sound, driving the app with clicks,
typing, keys and scrolling, captions, key badges and click ripples drawn over it, GIFs, and narration voiced by macOS
or [voicebox](https://github.com/jamiepine/voicebox), with clicks timed to its words and the app's sound ducked
under it, zoom (onto an element, a point or the cursor), speed-ups and cuts, and an intro and an outro with titles over a
colour, an image or a video, all changeable without recording again except which element a zoom is on. The tape language
is in PLAN.md. Captions are drawn at render time, so `reel render` picks up a changed caption without recording again.

While a tape plays it takes the mouse and keyboard; it stops rather than type into another app.

A web page instead of an app (macOS; WebKit by default, or `Set Browser chromium`; your mouse stays yours):

```
Open https://example.com
Output signup.mp4
Set Viewport 1280x800

Click "Sign up"
Click "Email"
Type "me@example.com"
Click css:"form button[type=submit]"
Wait "Welcome"
```

## Install

```sh
brew install --cask mpdreamz/tap/reel
reel doctor             # what is granted, and which browsers web tapes can use
```

reel runs on macOS 15 or later on Apple silicon. It records with Screen Recording and drives apps with Accessibility,
both granted to the terminal it runs in; the first recording asks. A web tape needs neither Accessibility nor a
browser: WebKit is built in.

From source: `mise run install` builds it into `~/.local/bin/reel`.
