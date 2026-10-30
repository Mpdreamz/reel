---
description: "Open a web page instead of launching an app, in WebKit (built in) or a Chromium-based browser."
---

# Web pages

```
Open https://example.com
Output signup.mp4
Set Viewport 1280x800

Click "Sign up"
Click "Email"
Type "me@example.com"
Click css:"form button[type=submit]"
Wait "Welcome"
```

`Open` takes `https://…`, `http://…`, `file://…` or a path to an `.html` file. Later in the reel, another `Open`
goes to another page. `Set Viewport` is the page's size in points (1280x800 unless set).

Every take starts in a fresh browser, with no cookies, storage or saved passwords, so a page records the same way each
time: a site that asks for cookie consent asks every take. [Skip it](zoom-speed-and-trim.md) with `Hide` … `Show`.

A web reel records the page alone, under the title bar, with the page's sound. It doesn't take your mouse or keyboard
and needs no Accessibility: reel drives the page itself and draws the cursor into the video afterwards.

## Which browser

| | |
|---|---|
| WebKit (the default) | Built into macOS, nothing to install. A window of reel's own; pages render as in Safari. |
| `Set Browser chromium` | The first of Chrome, Chromium, Brave and Edge that is installed, else the newest Chromium Playwright downloaded. Started on a fresh profile, without tabs or an address bar, and removed afterwards. |
| `Set Browser /Applications/Brave Browser.app` | That browser. |

A browser the reel asks for that isn't there refuses the take rather than fall back to another. `reel doctor` says
what `chromium` would be.

WebKit can't be hovered and scrolls by script: macOS only sends mouse moves and wheel events to the active app,
and a tool started from a terminal can't make itself active. If a demo needs hover effects or wheel events, use
Chromium, which takes both over DevTools. WebKit's sound plays in helper processes it shares with Safari, so sound
Safari plays during a take is recorded too.

See [Elements](../reels/elements.md) for how a page's elements are named.
