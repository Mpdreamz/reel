---
description: "A value that differs by profile or output type, in one line."
---

# Conditions

A value can differ by profile:

```
Set Quality social|feed ? 70 : github ? 50 : 65
```

Conditions are read left to right. The first that holds chooses its value; the last value is for when none does, or
when no profile is rendering. A condition is a profile's name, or names joined by `|`.

A line that starts with `:` continues the line before it, so a long chain lines up:

```
Caption github ? "brew install --cask mpdreamz/tap/reel"
        : social|feed ? "Follow for more"
        : "Recorded with reel"
```

Only one profile renders at a time, so a condition inside a chosen value could never matter. It's refused, and a chain
like the one above is all you need.

## Output types

A condition can also name an output type, `mp4`, `mov` or `gif`. Then each type is rendered from its own reading:

```
Caption gif ? "Short" : "The long version, for the movie with sound"
```

## Where they work

Conditions work where rendering decides: `Set`, `Caption`, `Intro` and `Outro`, in a tape, a preset or a profile. A
condition covers all of a command's values:

```
Outro social ? "Recorded with reel" "github.com/Mpdreamz/reel"
    : "Recorded with reel" "brew install --cask mpdreamz/tap/reel"
```

Anything that happens while recording (`Say`, `Type`, `Click`, the window's size, the voice) is the same for every
profile, since one recording serves them all; a condition there is refused. So is one that names a profile that
doesn't exist.
