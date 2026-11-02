---
description: "reel run, record, render, check, profiles and doctor."
---

# Command line

```
reel [run] <reel> [--profile <name> ...] [--events <path>]
reel record <reel> [--events <path>]
reel render <reel> [--profile <name> ...] [--events <path>]
reel check <reel> [--profile <name> ...]
reel profiles [<reel>]
reel doctor
```

| Command | |
|---|---|
| `reel <reel>`, `reel run <reel>` | Records the reel, then renders every output. Every profile it will render is read first, so a mistake stops it before recording. |
| `reel record <reel>` | Only records the take, into `.reel/<reel name>/` next to the reel. |
| `reel render <reel>` | Only renders the outputs from the last take. Refused when an action in the reel has changed since. |
| `reel check <reel>` | Reads the reel and says what it would do: what it opens, the narration, its actions and captions, and every file it would write, for each profile. Records nothing. |
| `reel profiles [<reel>]` | The built-in profiles and what each sets; with a reel, its profiles too, with where each setting comes from. |
| `reel doctor` | Whether Screen Recording and Accessibility are granted (it doesn't ask), and which browser `Set Browser chromium` would use. |
| `reel --version` | The version. |

`--profile` renders only some profiles: repeat it, or separate names with commas (`--profile github,social`). A reel
that lists its profiles (`Set Profiles`) renders only from among them.

## Progress events

`run`, `record` and `render` say what they are doing as they do it, one JSON object per line: the run starting, each
scene, each step starting and ending (`"index": 3, "count": 14`), capture starting (the part of the screen recorded,
in global points) and ending, each pass of the render with its profile, Output and how far along it is
(`"fraction": 0.42`; `draw`, `render`, `frame`, `join`, `tracks`, `encode`, `gif`, with `attempt` when a pass is
redone to fit `MaxSize`), each file written, every line printed, and the run ending or failing.

```json
{"at":1793605741592,"count":4,"index":2,"kind":"step","line":8,"phase":"start","pid":23726,"source":"Go line 2"}
{"at":1793605742669,"kind":"pass","pass":{"attempt":1,"fraction":0.5,"name":"encode","output":"demo-github.mp4","profile":"github"},"pid":23726}
```

Every run writes them to `~/Library/Application Support/reel/runs/<pid>.jsonl`, where the companion app reads them;
`--events <path>` also writes them to that file, and `--events -` to standard error. A track of a reel of tracks adds `"track"`. What is printed is the same
either way, and nothing reads the events back: they never change what a run does.

Warnings, such as a relative path that leads out of the git repository, go to standard error. Exit status is
non-zero on any error, with the line it was on.

## The take

`.reel/<reel name>/` holds the take and what rendering derives from it:

| File | |
|---|---|
| `take.mov` | The recording: the window and its sound. |
| `take.json` | The window's size and scale, and when each step ran. |
| `voice/` | Each narrated line, voiced and cached. |
| `edit.json` | What of the take was kept, and how fast. |

Add `.reel/` to your `.gitignore`.
