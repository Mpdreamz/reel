---
description: "Reels that run at the same time: named steps, and one reel waiting for another's."
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
