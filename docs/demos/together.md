---
description: "Reels and subjects at the same time: named steps, waiting for each other, and tracks recorded together."
---

# Reels together

```
# musicbox.reel
Launch dev.musicbox.app
Wait #lanes as ready
Click #play as play
Key space as stop
```

```
# showcase.reel, a terminal that runs the reel above
Screen terminal
Output showcase.mp4
Type "reel musicbox.reel"
Key return as run
Wait for ready
Caption "Musicbox is up"
Wait for stop to end
```

Any step can end with `as <name>`, a name other reels can wait for. `Wait for <name>` waits until a step of that name,
in another reel running at the same time, has started; `Wait for <name> to end` until it has finished. It works both
ways: `musicbox.reel` could `Wait for run` as well.

| Command | |
|---|---|
| `… as <name>` | Names the step: letters, digits, `-` and `_`, starting with a letter, each name once in a reel. |
| `Wait for <name>` | Until a step of that name, in another reel, has started. One that already has counts. |
| `Wait for <name> to end` | Until it has ended. |

A wait gives up after `WaitTimeout` (10s unless set) and says what it last heard:

```
line 8: waited 10s for ready to start on the channel; the last it heard was musicbox.reel line 3 (ready) starting
```

`reel check` lists a reel's named steps and what it waits for.

## Tracks: several subjects in one reel

```
Screen terminal as term
  Set Columns 84
  Wait for opened
  Type "reel musicbox.reel"
  Key return as run
  Wait /wrote/ as done

Screen code as script
  Code musicbox.reel as opened
  Wait for run

Output showcase.mp4
Output@9:16 showcase-tall.mp4
Say "One command records a whole demo."
Wait for done
```

A reel can record several subjects at once. Each is a track: its line says what it records and ends with `as <name>`,
and its steps are indented under it. A track can also be a file of its own, `With term.reel as term`, which is any
reel without `Speed` or `Hide` (its Outputs, intro and outro left out). Every track is read top to bottom, as its own
reel would be, and they all play at the same time; they meet only through named steps, with `Wait for`.

The unindented steps are the director's: `Say`, `Caption`, `Sleep`, `Wait for`, `Wait [marker]`, `Speed` and
`Hide` … `Show`, over every track. A step that acts on a subject belongs indented under its track.

`Speed` and `Hide` … `Show` are the director's only. In a track they would speed up or cut that track alone, and it
would drift out of step with the others. A track that has them, indented or in its file, is refused at the line:

```
line 9: Speed in a track plays it out of step with the other tracks: put it on the director, unindented in the reel of tracks, to speed them all up
```

- **Real input takes turns.** Two app tracks clicking at the same moment would share one mouse, so their steps take
  turns. Typing into a terminal or a code screen uses no real input and doesn't wait.
- **A deadlock stops at once.** When every track waits for a step only another of them would take, the take stops
  with who waits for what: `no track can go on: script waits for run; term waits for opened`. A wait for a step no
  track has could come from a reel run in a terminal, so that one waits its `WaitTimeout`.
- **Each track records into a take of its own**, under `.reel/<reel>/tracks/<name>/`, with the moment it started, so
  render lines them up.

In render, each track is rendered as its own reel would be (its overlays and zooms), then all of them are drawn
together for each shape the Outputs take: side by side in a wide cut, stacked in a tall one, each as a window on the
backdrop. The director's narration and captions go over the whole, then the intro and outro.

## Directing the tracks

```
Screen terminal as term
  Type "reel musicbox.reel"
  Key return as run
  Wait /wrote/ as done

Screen code as script
  Code musicbox.reel
  Follow
  Wait for done to end

Attach dev.musicbox.app as app

Output showcase.mp4
Output@9:16 showcase-tall.mp4
Set Layout (term / script) | app
Say "One command records a whole demo."
Wait for app
Spotlight app
Say "Here is what it records."
Pip@smooth,1s term over app
Wait for done
Pip off
```

The director moves the camera over the tracks, as `Zoom` moves it over a window: each move eases from where
everything is to where it goes, at render time, so a move changes without a new take. A move happens at the end of
the director's step before it, as a caption does.

| | |
|---|---|
| `Set Layout <arrangement>` | How the tracks share the canvas to start with. Side by side when not set. |
| `Layout <arrangement>` | Arranges them anew; ends a fullscreen or a picture-in-picture. |
| `Split <share>% …`, `Split off` | The top cut's parts get these shares, in order; off gives them back their own. |
| `Spotlight <track>`, `Spotlight off` | That track larger (70% of each cut it is in), the others smaller. |
| `Fullscreen <track>`, `Fullscreen off` | That track alone, as large as the canvas holds it; the others fade. |
| `Pip <track> [over <track>] [corner]`, `Pip off` | That track small in a corner, over the rest or over one; what it is not over fades. Corners: `top-left`, `top-right`, `bottom-left`, `bottom-right` (the default). |

Each move takes `@<easing>,<duration>`, as a zoom does (`Fullscreen@snap app`, `Pip@smooth,1s term`); a move eases
in and out over 600ms unless it says.

An arrangement names the tracks with `|` between those side by side and `/` between those one above the other,
grouped with parentheses: `(term / script) | app` is the terminal over the script, beside the app. A track it leaves
out is not shown. A part may carry its share of its cut, `term 40% | app`; the parts without one share what is left
by their own sizes. Without shares, a cut is as large as the canvas holds it at the tracks' own shapes; with them, it
fills the canvas and each track is as large as its share holds it.

- **A tall cut stacks.** An arrangement is written for a wide canvas; in a tall Output, each `|` becomes `/`, so
  `(term / script) | app` is three tracks one above the other.
- **Each profile its own.** A move or a layout can differ by profile with a condition, as a caption can:
  `Set Layout social ? term / app : term | app`, `Spotlight social ? app : off`.
- **A track grows in when it starts.** One that starts later than the rest (an `Attach`ed app, typically) is left
  out until its first frame, then the others make room as it grows in.

## An app something else opens

```
Screen terminal as term
  Type "reel musicbox.reel"
  Key return as run

Attach dev.musicbox.app as app

Output showcase.mp4
Wait for app
Say "And there it is."
```

`Attach <bundle id or .app path> as <name>` is a track that launches nothing: it waits for that app to open (here,
launched by the reel the terminal runs) and records its window from then on, as an app track would. It says its name
on the channel when the window shows, so the other tracks and the director `Wait for app`. Steps under it, if any,
play once it has. It records for as long as the rest of the reel plays, or until the app quits. An app already open
is attached at once; one that takes long to open has `WaitTimeout`, and at least a minute. Recording an app needs
Screen Recording, as any app reel does.

## Following a reel as it runs

```
Screen terminal as term
  Type "reel musicbox.reel"
  Key return as run
  Wait /wrote .*gif/ as done

Screen code as script
  Code musicbox.reel
  Follow
  Wait for done to end
```

`Follow` in a code screen marks the line of the reel it shows that is running right now, wherever it runs on the
channel (here, in the terminal track): a bar across the line and a `▶` by its number, the view easing to keep it in
sight, moving on as each step starts. A line that ran before `Follow` shows from that moment. `Follow off` stops; so
does giving the pane another file, or the track ending, so a track that should follow to the end waits for it, as
above.

`Wait for done` would not do there: `done` is the name of a `Wait`, which starts the moment its waiting does. A track
that waits for another to finish waits for its last step `to end`.

## How reels hear each other

Reels running together share a channel: a file every reel appends to as each step starts and ends, and reads for
its waits. Its path is in `REEL_CHANNEL`. A terminal screen gives its shell a channel, so a reel run in it is on the
same one as the reel recording it, with nothing to set up. Two reels started by hand meet when both are given the
same path, a new one each time: `REEL_CHANNEL=/tmp/run1 reel a.reel` and `REEL_CHANNEL=/tmp/run1 reel b.reel`.

## A reel on its own

A reel that names steps and waits for others still runs on its own: with no channel, a `Wait for` is skipped, and
says so. `reel musicbox.reel` records as it always did.

A `Wait for` a step of the same reel is refused: its steps run in order, so by then that step has passed, or never
comes.
