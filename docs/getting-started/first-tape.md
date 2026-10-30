---
description: "Record a first tape: a window, then a click, a caption, a voice and a GIF."
---

# Your first tape

A tape is a text file ending in `.reel`. The smallest one records an app's window for a few seconds:

```
# hello.reel
Launch com.apple.TextEdit
Output hello.mp4
Sleep 3s
```

```sh
reel hello.reel
```

reel opens TextEdit, waits for its window, records it for three seconds and writes `hello.mp4` next to the tape. The
recording itself, the take, is kept in `.reel/hello/`, so changing what is drawn over it doesn't need a new recording.

## Make it do something

```
Launch com.apple.TextEdit
Output hello.mp4
Output hello.gif
Set Size 1200x800

Key cmd+n
Caption "A new document"
Type "Written by a tape.\n"
Key cmd+a
Sleep 1s
```

- `Set Size` sizes the window before recording starts.
- `Key cmd+n` presses the keys; a badge shows `⌘N` in the video.
- `Caption` shows text along the bottom from that point on.
- `Type` types a character at a time; `\n` is return.
- `Output hello.gif` writes a GIF as well, from the same recording.

`reel check hello.reel` reads the tape and says what it would do, without recording anything.

## Narrate it

```
Set Voice system
Say "TextEdit opens a new document."
Key cmd+n
Say@over "Then we type [type] a line."
Wait [type]
Type "Written by a tape.\n"
```

`Say` speaks a line in macOS's voice and waits for it to finish. `Say@over` speaks and carries on, and
`Wait [type]` waits until the voice reaches the `[type]` marker, so the typing starts on that word. See
[Narration](../demos/narration.md).

## Change it without recording again

Captions, narration placement, zooms on a point, speed-ups, cuts, title cards and every output setting are applied
when rendering. Edit them, then:

```sh
reel render hello.reel
```

Only a change to what happens in the app (a click, typed text, a spoken line) needs `reel hello.reel` again.
