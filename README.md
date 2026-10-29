# reel

Record demos of macOS apps from a script. Like [VHS](https://github.com/charmbracelet/vhs), but for windows instead
of terminals, and with the app's sound.

```
# demo.tape
Output demo.mp4
Set Size 1280x800

Launch com.example.musicbox
Wait "Library"
Caption "Pick a track"
Click "Midnight City"
Caption "Space plays it"
Key space
Sleep 4s
```

```sh
reel check demo.tape    # parse it and say what it would do
reel demo.tape          # record, then render every Output
reel record demo.tape   # only capture the take (.reel/demo/)
reel render demo.tape   # only render the outputs from the last take
reel doctor             # Screen Recording and Accessibility
```

Status: milestones 1 to 3 of [PLAN.md](PLAN.md): recording a window with its sound, driving the app with clicks,
typing, keys and scrolling, and captions, key badges and click ripples drawn over it. GIFs are next. The tape language
is in PLAN.md. Captions are drawn at render time, so `reel render` picks up a changed caption without recording again.

While a tape plays it takes the mouse and keyboard; it stops rather than type into another app.

## Install

```sh
mise run install        # ~/.local/bin/reel
```

Requires macOS 15. The first recording asks for Screen Recording for your terminal; a tape that drives the app
needs Accessibility too (`reel doctor`).
