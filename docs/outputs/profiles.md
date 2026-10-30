---
description: "Render every output once for GitHub, social feeds, your site and more, each fitted to where it's going."
---

# Profiles

```
Output //docs/media/musicbox.mp4
Output //docs/media/musicbox.gif
Set Profiles github, web, social
```

A profile is a named set of render settings for where a video is going. `Set Profiles` renders every output once
for each, from the one recording, with the profile's name in the file name:

```
musicbox-github.mp4    musicbox-github.gif
musicbox-web.mp4       musicbox-web.gif
musicbox-social.mp4    (social writes no GIFs)
```

The name is there whenever a profile is, so a file's name doesn't depend on how many profiles were rendered.

## The built-in profiles

| Profile | For | Sets |
|---|---|---|
| `highest` | Archiving, editing later | `Codec prores` (ProRes 422 in a `.mov`, H.264 at quality 100 in an `.mp4`); GIFs full width, 30 fps |
| `github` | READMEs, issues, pull requests | 1920 wide, `MaxSize 10MB` (GitHub's limit for an attached video or GIF), GIFs 800 wide |
| `web` | Landing pages, docs sites | 1920 wide, quality 60, 30 fps |
| `social` | YouTube Shorts, TikTok, Reels | 1080x1920, quality 70, 30 fps, `MaxSize 250MB`, `MaxLength 3m`, subtitles, no GIFs |
| `feed` | X, Bluesky, Mastodon, LinkedIn | 1920x1080, 30 fps, `MaxSize 40MB`, `MaxLength 140s`, subtitles, no GIFs |
| `square` | Instagram and LinkedIn feeds | 1080x1080, 30 fps, `MaxSize 40MB`, `MaxLength 140s`, subtitles, no GIFs |

The social limits are the strictest common ones, from third-party guides where a platform publishes none: Mastodon's
40 MB default, X's 2:20 for standard accounts, TikTok's 287 MB on mobile. Subtitles are on because feeds play muted.

`reel profiles` lists them with every setting; `reel profiles demo.reel` lists what a tape can render for, its
[presets'](presets.md) profiles included, with where each setting comes from.

## How a profile applies

A profile is `Set` lines, applied after the tape's own: a plain `Set` in the tape never cancels a profile. To give a
profile a different value, name it in a [condition](conditions.md):

```
Set Quality social ? 75 : 60
```

A profile can only change what rendering decides. The window size, the frame rate it records at, the voice and the
browser are fixed when recording, since one recording serves every profile.

## Rendering some of them

```sh
reel render demo.reel --profile social
reel render demo.reel --profile github,web
```

`--profile` on `run`, `render` and `check` picks among the tape's profiles, or among all of them when the tape lists
none. A name the tape doesn't list, or no profile has, is refused before anything is recorded.

To make your own, or change a built-in one, see [Presets](presets.md).
