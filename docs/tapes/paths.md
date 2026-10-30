---
description: "Paths in tapes and presets are relative to their file, from home with ~, or from the git root with //."
---

# Paths

A path in a tape (an `Output`, an app to `Launch`, a background, an `Import`) is one of:

| Write | From |
|---|---|
| `demo.mp4`, `../docs/demo.mp4` | The folder the file it's written in is in. |
| `~/Movies/demo.mp4` | Your home folder. |
| `/tmp/demo.mp4` | The root of the disk. |
| `//docs/media/demo.mp4` | The root of the git repository the tape is in. |

`//` lets a tape or a preset name a file in the repository without counting `../`, and keeps working when the tape
moves. Outside a git repository it is an error.

A relative path that leads out of the repository still works, with a warning:

```
warning: line 3: ../../outside.mp4 leads outside the git root /Users/me/Projects/app, so it works only where that sits next to the repository
```

It works on your Mac, but not on one where the repository sits somewhere else. Absolute paths and `~` don't warn:
they say plainly where they lead.

In a preset, paths are relative to the preset, not to the tape that imports it.
