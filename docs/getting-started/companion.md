---
description: "Reel Companion, a menu bar app: which step, scene and pass a run is on, and a frame on the window being recorded that the take never shows."
---

# The companion app

Reel Companion lives in the menu bar and shows what every run of reel is doing:

- while it records: the scene of a reel of scenes, and the step each subject is on (`line 12 · Click "Play" · 3/14`);
- while it renders: the pass (drawing, rendering, framing, joining, encoding, writing a GIF), which profile and which
  Output it is for, how far it is, and which try when a movie or GIF is made again to fit `MaxSize`;
- once it is done: whether it ended well or how it failed, and the files it wrote, each shown in the Finder on a click.

Its symbol turns red while a take records, and fills a ring while a render runs.

While an app or a web page records, it draws a red frame round the window and a pill beside it with the step. The take
never shows them: reel keeps every other app out of what it captures, the companion included, and the companion draws
only once reel has said it is kept out. They let every click through, and the companion never comes to the front, so
reel's clicks and keys still reach the app.

## Running it

reel opens it, out of sight, when an app or web reel starts recording and it is installed but not running. Set
`REEL_COMPANION=0` to leave it closed. To build and open it from a checkout:

```
mise run companion
```

It reads what runs write to `~/Library/Application Support/reel/runs/` (see [progress events](../reference/cli.md#progress-events));
it needs no permission of its own.
