---
description: "reel run, record, render, check, profiles and doctor."
---

# Command line

```
reel [run] <reel> [--profile <name> ...]
reel record <reel>
reel render <reel> [--profile <name> ...]
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
