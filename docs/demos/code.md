---
description: "Walk through source code in an editor of reel's own: no app to install, no window, no permissions."
---

# Code

```
Screen code
Output walkthrough.mp4
Set Viewport 1100x620
Set FontSize 20

Code Sources/SpeechClock.swift
Say "This is how reel keeps one line from talking over the next."
Go "func say"
Focus lines 9-20
Mark "max(now, speechEnd)" 1
Callout "max(now, speechEnd)" "when it's reached, or after the line before"
Say "A line starts when the reel reaches it, or when the one before it ends."
Callout off
Mark off
Focus off
Code Sources/SpeechClock.java at "public double[] say"
Key end
Key return
Zoom cursor 1.5x
Type "// typed at your pace"
```

`Screen code` records an editor of reel's own instead of an app or a page. It's
[Monaco](https://microsoft.github.io/monaco-editor/), the editor in VS Code, in a page nobody sees, shipped with reel:
nothing to install, no window on your screen, and no Screen Recording or Accessibility. Code is coloured as your editor
colours it, in dozens of languages (Swift, TypeScript, JavaScript, Python, Rust, Go, Java, C#, Kotlin, shell, HTML,
CSS, JSON, YAML, Markdown and more), picked from the file's extension.

`Set Viewport` is the screen's size in points (1280x800 unless set), and `Set FontSize` its text (18 unless set).

## Files and places

| Command | |
|---|---|
| `Code <file>` | Shows the file, with its name, its folder from the git root and its language in a header. The next file fades up in its place. |
| `Code <file> lines <a>-<b>` | Only those lines, numbered as in the file. |
| `Code <file> at line <n>`, `Code <file> at "<text>"` | Opens with the cursor at a line or the first match of the text, scrolled into view. |
| `Go line <n>`, `Go "<text>"` | Moves the cursor there; the view eases to it when it's out of sight. Line numbers are the file's. |

A place that isn't in the file stops the take at its line: `"func pause" is not in SpeechClock.swift`.

## Between files

```
Code Synthesizer.swift
Code@slide-left Voicebox.swift at "struct Voicebox"
Code@crossfade Synthesizer.swift
Split Voicebox.swift at "struct Voicebox"
Link "protocol Synthesizer" -> "struct Voicebox: Synthesizer" "conforms to"
Link "func speak" -> "func speak" "implements"
Pane right
Peek "profileID()" Voicebox.swift at "func profileID"
```

| Command | |
|---|---|
| `Code@<transition> <file>` | The file before moves out as this one comes in: `crossfade`, `fade`, `slide-left` and the other slides, `zoom`, the wipes, or `cut`, with an easing and a duration, as an [intro](intro-and-outro.md) takes them. Without one, the new file fades up. |
| `Split <file> [lines <a>-<b>] [at …]` | Opens the file in a second pane, sliding in from the right to take half the screen. Steps then act on it. |
| `Pane left`, `Pane right` | Which pane `Code`, `Go`, `Type`, `Focus`, `Mark`, `Callout` and `Peek` act on, and where the caret shows. |
| `Split off` | Back to the left pane, full width. |
| `Peek "<text>" <file> [lines <a>-<b>] [at …]` | Opens the file in a box under the line with the text, as an editor peeks a definition: up to 8 lines, scrolled to its place, that line highlighted. `Peek off` closes it. |
| `Link "<a>" -> "<b>" ["<label>"]` | An arrow from the first `a` to the first `b`, drawing itself in, with a label. Split, it goes across: `a` is looked for on the left first, `b` on the other side. In one pane, it curves out past the end of both lines. Links add up until `Link off`. |

Relations are declared in the reel: reel colours code but doesn't understand it, so it can't find what implements
what on its own. The texts are anchors, matched exactly, as `Mark` matches them.

## Pointing things out

| Command | |
|---|---|
| `Focus lines <a>-<b>` | Dims every other line, until `Focus off`. |
| `Mark "<text>" [n]` | A box around the first match of the text, numbered `n` when given. Marks add up until `Mark off`. |
| `Callout "<text>" "<label>"` | A bubble saying the label, beside the text's line where it fits, so it covers no code. Until the next callout or `Callout off`. |

These are part of the take: changing one records the screen again, which takes seconds and needs nothing.

## Typing

`Type` types at the cursor, over any selection, at `TypingSpeed` or its own `Type@<duration>`. `Key` takes the keys
an editor does: `return` (keeping the line's indent), `tab`, `space`, `backspace`, `forwarddelete`, `escape`, the
arrows, `home`, `end`, `pageup` and `pagedown`, with `shift+` to select (`Key shift+left 5`).

`Zoom cursor` follows the caret as it types; `Zoom @x,y` zooms on a point of the screen. `Say`, `Caption`, `Speed`,
`Hide` and `Show`, intros and outros, framing and every output work as they do for an app.

## What a code screen can't do

There's no app or page, so `Click`, `Scroll`, `Wait <element>`, zooming on an element, `Set Size` and `Set Browser`
are refused at their line. One reel records one thing: an app, a page or a code screen.

## The same every time

A code screen isn't captured, it's drawn: the steps play on the take's own clock and each frame is drawn when its time
comes. The same reel makes the same take every time.
