---
description: "Every Set, its values and default, and whether it is fixed when recording."
---

# Settings

`Set <setting> <value>`, in the reel's setup or a [preset](../outputs/presets.md). **Recording** settings are fixed
when the take is made and can't differ by profile; changing one needs a new recording. **Render** settings change
with `reel render`, and profiles and [conditions](../outputs/conditions.md) can set them.

## Recording

| Setting | Values | Default |
|---|---|---|
| `FrameRate` | Frames a second captured, 1 to 120 | 60 |
| `Audio` | `on`, `off`: record the app's sound | on |
| `Size` | `<width>x<height>` in points: the app window's size | as it opens |
| `Viewport` | `<width>x<height>` in points: a web page's size | 1280x800 |
| `Browser` | `webkit`, `chromium` or an `.app` path | webkit |
| `TypingSpeed` | Pause after each typed character | 50ms |
| `WaitTimeout` | How long `Wait` and `Click` look for an element | 10s |
| `Voice` | `system`, `system:<voice>`, `voicebox:<profile>` | system |
| `VoiceServer` | voicebox's address | http://127.0.0.1:17493 |
| `VoiceSeed` | voicebox's seed, 0 and up | 1 |
| `VoiceLanguage` | voicebox's language, two letters | en |

## Overlays and narration

| Setting | Values | Default |
|---|---|---|
| `KeyBadges` | `on`, `off` | on |
| `ClickRipples` | `on`, `off` | on |
| `Subtitles` | `on`, `off`: each `Say` as a caption | off |
| `Ducking` | The app's sound under the voice, 0% to 100% | 25% |
| `VoiceVolume` | 0% to 100% | 100% |
| `AppVolume` | 0% to 100% | 100% |
| `ZoomEasing` | `linear`, `ease-in`, `ease-out`, `ease-in-out`, `smooth`, `snap` | ease-in-out |
| `ZoomDuration` | How long a zoom moves | 400ms |
| `IntroBackground`, `OutroBackground` | `#rrggbb`, an image, or a video (its sound plays) | near-black |

## Framing and outputs

| Setting | Values | Default |
|---|---|---|
| `Background` | `#rrggbb`, an image or a video (looped, silent): frames every output | none |
| `Padding` | Room around a framed recording, 0% to 30% of the canvas's shorter side | 6% |
| `Shape` | `16:9`, `1:1`, `9:16` or `<w>x<h>`: every output with no shape of its own | none |
| `Quality` | 1 to 100 | 65 |
| `Codec` | `h264`, `hevc`, `prores` | h264 |
| `VideoWidth` | 100 to 8000 pixels, never wider than the recording | full size |
| `VideoFrameRate` | 1 to 120, never more than recorded | as recorded |
| `MaxSize` | `10MB`, `500KB`, `1.5GB` | no limit |
| `MaxLength` | A duration | no limit |
| `Formats` | `mp4`, `mov`, `gif`, comma separated: write only these | all |
| `GifWidth` | 100 to 4000 pixels | 800 |
| `GifFrameRate` | 1 to 50 | 15 |
| `GifColors` | 2 to 256 | 256 |
| `Profiles` | Profile names, comma separated | none |
