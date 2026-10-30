---
description: "How a reel is laid out: what it records, its setup, and the steps it plays."
---

# Writing reels

A reel is a `.reel` file, one command per line, in three parts:

```
# 1. What it records: the first line (after any Import lines and comments).
Launch ~/Projects/musicbox/build/App/Musicbox.app

# 2. Setup: what to write and how. Nothing is recorded yet.
Output musicbox.mp4
Set Size 1440x900
Intro "Musicbox" "Chord progressions, sketched and heard"

# 3. Steps: recording starts at the first one.
Wait #lanes
Key space
Say "The chords lane drives the others."
```

- **What it records.** `Launch` an app, by bundle id or path, or `Open` a web page. Everything after is read knowing
  which, so a setting for the other kind (`Set Viewport` in an app reel, `Set Size` in a web reel) is refused at its
  line rather than ignored.
- **Setup** is `Output`, `Set`, `Intro`, `Outro` and `Profile`, before the first step. A reel needs at least one
  `Output`.
- **Steps** are everything else: `Click`, `Type`, `Key`, `Say`, `Caption`, `Zoom`, and the rest. See
  [Commands](../reference/commands.md).

## Comments

`#` starts a comment at the start of a line, or after a space:

```
Set Size 1440x900   # the window, in points
Click #play         # #play here is an identifier, not a comment
```

`#` straight after a word is part of it: `#play` is an element's identifier and `#1d2b3a` a colour.

## Values

- **Durations:** `500ms`, `2s`, `1.5s`, `1m`, or a bare number of seconds.
- **Text** in double quotes: `Type "hello"`, `Caption "Saved"`. `\n` is return, `\"` a quote.
- **Options** after `@` on the command: `Type@20ms "fast"`, `Say@over "…"`, `Zoom@ease-out,600ms #list`,
  `Intro@slide-up "Title"`.

## When a line is wrong

reel reads the whole reel before it records anything, and an error names its line:

```
$ reel check demo.reel
Error: line 7: 'cmd+nope' is not a key; write a key name such as return or a, with modifiers: cmd+s
```

`reel check` reads a reel and says what it would do: what it launches, the narration, how many actions and
captions, and every file it would write, for each profile.

| | |
|---|---|
| [Elements](elements.md) | How a reel names what to click, wait for and zoom on. |
| [Paths](paths.md) | Relative paths, `~`, and `//` for the root of the git repository. |
