---
description: "Record the command line: a real shell in a terminal of reel's own, with waits on its output, redaction and marks."
---

# Terminal

```
Screen terminal
Output build.mp4
Set Columns 84
Set Rows 20
Set Redact /sk-[A-Za-z0-9]+/

Type "swift build"
Key return
Speed 4x
Wait /Build complete/
Speed off
Mark "Build complete" 1
Callout "Build complete" "from scratch"
Say "And it builds."
```

`Screen terminal` records a terminal instead of an app or a page. reel draws it with
[xterm.js](https://xtermjs.org), the terminal in VS Code, and runs a real `zsh` in it: the commands run, so a reel can
only show what's installed. Like a [code screen](code.md), it needs no window and no Screen Recording or Accessibility.

The shell starts clean, so a reel looks the same on every Mac:

- a home folder of its own, with no history and none of your shell's setup (`.zshrc`, plugins, aliases);
- a plain prompt: the folder's name, then reel's chevron;
- your `PATH` and `LANG`, so the tools you have are there;
- the reel's folder as the working directory, or `Set WorkingDirectory`.

## Its size and look

| Setting | |
|---|---|
| `Set Columns <n>`, `Set Rows <n>` | The terminal's size in characters, 80 by 24 unless set. It sizes the screen. |
| `Set FontSize <points>` | The text, 18 unless set. |
| `Set Theme <file>` | A [Ghostty](https://ghostty.org) theme: `background`, `foreground`, `cursor-color`, `selection-background` and the 16 `palette` colours. reel's own colours otherwise. |
| `Set Title "<text>"` | The window's title, the folder and `zsh` unless set. |
| `Set WorkingDirectory <path>` | Where the shell starts. `//` is the git root, as in every path. |

A terminal's size is fixed for a take: every profile renders the same one, framed as any recording is.

## Typing and waiting

`Type` types at `TypingSpeed`, and the shell echoes it. `Key` sends `return`, `tab`, `space`, `backspace`,
`forwarddelete`, `escape`, the arrows, `home`, `end`, `pageup`, `pagedown`, and `ctrl+` a letter (`Key ctrl+c`).

Commands take as long as they take. Wait for them rather than guessing with `Sleep`:

| Command | Waits until |
|---|---|
| `Wait /<regex>/` | What the shell printed since the last thing typed matches, colours left out: `Wait /Build (complete\|succeeded)/`. |
| `Wait quiet [duration]` | Nothing has been printed for that long, 500ms unless given. |
| `Wait exit` | The command running has ended and the prompt is back. |

Each gives up after `WaitTimeout` (10s unless set) and stops the take, with the last lines printed:

```
line 6: waited 10s for /Build complete/; the last lines were:
error: no such module 'Engine'
```

A slow command needn't be watched in full: `Speed 4x` … `Speed off` around the wait, or `Hide` … `Show` to cut it.
`Hide` also hides setup the demo shouldn't show, such as `cd` into a folder or a `clear`.

## Pointing things out

`Mark "<text>" [n]` puts a box around the last place the text shows on screen, the newest output first, numbered
`n` when given. `Callout "<text>" "<label>"` puts a bubble by it, beside the line where it fits. Both scroll up with
their line as more is printed, and `Mark off` and `Callout off` take them away.

## Keeping secrets out

`Set Redact /<regex>/` covers whatever matches on screen with dots, whether a command printed it or it was typed: a
match is covered from its first character as it's typed, and grows as more of it is. Give as many as you need, one per
line. The pattern is matched line by line on what the screen shows, so a secret that wraps onto a second line isn't
found. Better still, keep secrets out of a reel: read them from your environment (`echo $TOKEN | tool login`).

## How a terminal is recorded

In two passes. The shell runs first, in real time, and reel keeps everything it prints with when it printed it. Then
the terminal is drawn from that, a frame at a time, the way a code screen is.
