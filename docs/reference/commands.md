---
description: "Every command a reel can hold."
---

# Commands

## What it records

| Command | |
|---|---|
| `Import <path>` | A [preset](../outputs/presets.md) to read first. Only on the first lines, before `Launch`, `Open` or `Screen`. |
| `Launch <bundle id or .app path>` | The app to record: a bundle id, or a path with a slash (`./Name.app`). reel waits for its first window. |
| `Open <url>` | A web page to record instead: `https://…`, `http://…`, `file://…` or an `.html` path. Later in the reel, goes to another page. |
| `Screen code` | A [code screen](../demos/code.md) to record instead: an editor of reel's own. |
| `Screen terminal` | A [terminal](../demos/terminal.md) to record instead: a real shell in a terminal of reel's own. |

## Setup

Before the first step.

| Command | |
|---|---|
| `Output <path>` | A file to write: `.mp4`, `.mov` or `.gif`. At least one. |
| `Output@<shape> <path>` | Framed on a canvas: `@16:9`, `@1:1`, `@9:16`, or an exact size such as `@1080x1920`. |
| `Set <setting> <value>` | See [Settings](settings.md). |
| `Intro "<title>" ["<subtitle>"] [duration]` | A title card before the demo. |
| `Outro "<title>" ["<subtitle>"] [duration]` | One after it. |
| `Intro [duration]`, `Outro [duration]` | The background video alone. |
| `Intro@<kind>,<easing>,<duration> …` | How it moves into the demo (an outro: out of it). See [Intro and outro](../demos/intro-and-outro.md). |
| `Profile <name> [extends <profile>] ["purpose"]` | A [profile](../outputs/presets.md), with indented `Set` lines under it. |

## Steps

| Command | |
|---|---|
| `Sleep <duration>` | Waits. |
| `Wait <element>` | Waits until the element shows, up to `WaitTimeout`. |
| `Wait [marker]` | Waits until the narration reaches a `[marker]` in an earlier `Say@over`. |
| `Click <element or @x,y>` | Glides the cursor there and clicks. |
| `Type "<text>"`, `Type@<duration> "<text>"` | Types a character at a time. `\n` is return, `\t` tab. |
| `Key <combo> [count]` | `return`, `a`, `cmd+s`, `ctrl+shift+tab`, `f5`, `fn+left`; repeated `count` times (1 to 100). |
| `Scroll <up\|down\|left\|right> [lines] [element or @x,y]` | Scrolls, over the element when one is named. |
| `Say "<text>"` | Narrates the line and waits for it to end. |
| `Say@over "<text>"` | Narrates and carries on. |
| `Say@<voice> "<text>"`, `Say@<voice>,over "<text>"` | Narrates in a voice named with `Set Voice <name> <voice>`. |
| `Caption "<text>" [duration]` | A caption from here until the next one, or for `duration`. |
| `Caption off` | Ends the caption showing. |
| `Zoom <element> [scale]` | Onto the element, locked and following it. Fitted, at most 4×, without a scale. |
| `Zoom @x,y [scale]`, `Zoom cursor [scale]` | Onto a point, or following the cursor; 2× unless a scale is given. Scales are 1× to 8×. |
| `Zoom off` | Back to the whole window. |
| `Zoom@<easing>,<duration> …` | A zoom with its own move. |
| `Speed <rate>x` … `Speed off` | Plays the stretch faster, above 1× up to 16×. |
| `Hide` … `Show` | Leaves the stretch out. A `Hide` with no `Show` runs to the end. |

## Code screens

After `Screen code`. See [Code](../demos/code.md).

| Command | |
|---|---|
| `Code <file> [lines <a>-<b>] [at line <n> \| at "<text>"]` | Shows a file, or lines of it numbered as in the file, the cursor at a line or the first match of the text. |
| `Go line <n>`, `Go "<text>"` | Moves the cursor there, easing the view to it. |
| `Focus lines <a>-<b>`, `Focus off` | Dims every other line. |
| `Mark "<text>" [n]`, `Mark off` | A box around the text, numbered `n`; boxes add up until `Mark off`. |
| `Callout "<text>" "<label>"`, `Callout off` | A bubble saying the label beside the text's line. |

## Terminals

After `Screen terminal`. See [Terminal](../demos/terminal.md). `Type`, `Key` (the keys a shell takes, and `ctrl+` a
letter), `Mark` and `Callout` work too.

| Command | |
|---|---|
| `Wait /<regex>/` | Until what was printed since the last thing typed matches. |
| `Wait quiet [duration]` | Until nothing has been printed for that long, 500ms unless given. |
| `Wait exit` | Until the command running ends and the prompt is back. |

Elements are `"Label"`, `#identifier`, `@x,y` points, or on a web page `css:<selector>`: see
[Elements](../reels/elements.md).
