---
description: "Share settings and profiles between tapes with an imported .reelpreset, and define profiles of your own."
---

# Presets

Settings and profiles a team shares live in a `.reelpreset` file, which tapes import on their first lines:

```
Import //demos/house.reelpreset
Launch ~/Projects/musicbox/build/App/Musicbox.app
Output //docs/media/musicbox.mp4
```

```
# house.reelpreset
Set Background //design/backdrop.png
Set Voice system:Samantha
Set Profiles github, web

Profile github
  Set GifColors 128

Profile docs extends web "Our docs site"
  Set VideoWidth 1440
  Set MaxSize 8MB
```

- **`Import`** lines come first, before `Launch` or `Open`; comments may come before them. A tape may import
  several, and a preset may import presets, in order. One that comes back round is an error.
- **`Set` lines** in a preset are defaults. They apply as the tape says what it records, before the tape's own
  settings, which override them. A [profile](profiles.md) overrides both.
- **Paths** in a preset are relative to the preset. `//` starts at the git root; see [Paths](../tapes/paths.md).
- A preset holds `Import`, `Set` and `Profile` lines, and nothing that records. An error in one names the file and
  line.

## Profiles of your own

```
Profile <name> [extends <profile>] ["what it is for"]
  Set <setting> <value>
  Set <setting> <value>
```

A profile is its line and the indented `Set` lines under it, in a preset or in a tape; it ends at the first line
that isn't indented.

- **A built-in name** amends that profile: `Profile github` and its settings add to github's own.
- **A new name** starts from the profile it extends, or from nothing.
- Names are lowercase letters, digits and dashes, and not an output type (`mp4`, `mov`, `gif`).
- A profile can't set what is fixed when recording (`FrameRate`, `Audio`, `Size`, `TypingSpeed`, `WaitTimeout`, the
  `Voice` settings, `Browser`, `Viewport`), or choose profiles.

`reel run` reads every profile it is about to render before it records, so a bad value is refused first.
