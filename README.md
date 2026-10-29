# reel

Record demos of macOS apps from a script. Like [VHS](https://github.com/charmbracelet/vhs), but for windows instead
of terminals, and with the app's sound.

```
# demo.tape
Output demo.mp4

Launch com.example.musicbox
Sleep 4s
```

```sh
reel demo.tape          # record, then render every Output
reel record demo.tape   # only capture the take (.reel/demo/)
reel render demo.tape   # only render the outputs from the last take
reel doctor             # Screen Recording and Accessibility
```

Status: milestone 1 of [PLAN.md](PLAN.md). Recording a window with its audio works; driving the app, overlays and
GIFs are next.

## Install

```sh
mise run install        # ~/.local/bin/reel
```

Requires macOS 15. The first recording asks for Screen Recording for your terminal.
