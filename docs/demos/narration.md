---
description: "Say lines voiced by macOS or voicebox, the reel timed by them, clicks landing on a word, the app ducked under the voice."
---

# Narration

```
Set Voice system
Set Ducking 30%
Set Subtitles on

Say "This is Musicbox, a sketchpad for chord progressions."
Say@over "Press space, [play] and every lane starts looping."
Wait [play]
Key space
```

- **`Say "<text>"`** speaks the line and waits for it to end before the next step.
- **`Say@over "<text>"`** starts the line and carries on with the next steps while it plays.
- **`Wait [marker]`** waits until the narration reaches a `[marker]` in an earlier `Say@over`, so an action lands on
  a word. Markers are letters, digits, `-` and `_`; they aren't spoken.

Lines never overlap: one starts when the line before it ends. The take runs until the last line has been said.

## Voices

| `Set Voice` | Speaks with |
|---|---|
| `system` (default) | macOS's own voice. Offline, nothing to install. |
| `system:Samantha` | That macOS voice. |
| `voicebox:<profile>` | A [voicebox](https://github.com/jamiepine/voicebox) profile, by name or id: a voice you cloned, running locally. |

For voicebox, `Set VoiceServer` is its address (`http://127.0.0.1:17493` unless set), `Set VoiceSeed` its seed
(`1`) and `Set VoiceLanguage` its language (`en`).

Every line is voiced before the app opens and cached in `.reel/<reel>/voice/`, by text, voice and seed, so an
unchanged line isn't voiced again. Nothing is played aloud while recording. The voice is mixed in when rendering.

Each stretch between markers is voiced on its own, which is how reel knows exactly when a marker is reached. The cost
is a small seam in intonation at each marker.

## The mix

| Setting | Default | |
|---|---|---|
| `Set Ducking <n%>` | 25% | The app's sound under the voice. It ramps down and back up over 0.2 s; lines close together duck as one. |
| `Set VoiceVolume <n%>` | 100% | The voice's level. |
| `Set AppVolume <n%>` | 100% | The app's level. |
| `Set Subtitles on\|off` | off | Each line as a caption while it plays. A caption showing at the time is cut around it. |

A GIF has no sound, so subtitles are how narration reaches one. The social [profiles](../outputs/profiles.md) turn
them on, since feeds play muted.

## Changing a line

A line's text, voice or seed is part of the take: the reel's timing came from it, and voiced again it may come out a
different length. Change one and record again. Volumes, ducking and subtitles change with a render.
