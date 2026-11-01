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

`Open` takes `https://…`, `http://…`, `file://…` or a path to an `.html` file, with a `#fragment` if you like
(`site/index.html#pricing`). Later in the reel, another `Open` goes to another page. `Set Viewport` is the page's size
in points (1280x800 unless set).

An `Open` of the page already showing does one of two things:

| | |
|---|---|
| Only the `#fragment` differs: `Open https://example.com/#pricing` after `Open https://example.com/` | Stays on the page and goes to the fragment, as a link to it would. Nothing loads; the step ends when the scroll settles. |
| The same address: `Open https://example.com/#pricing` again | Loads the page again, so it starts over: its animations play again and what was typed is gone. |

Every take starts in a fresh browser, with no cookies, storage or saved passwords, so a page records the same way each
time: a site that asks for cookie consent asks every take. [Skip it](zoom-speed-and-trim.md) with `Hide` … `Show`.

A web reel records the page alone, with the page's sound. It doesn't take your mouse or keyboard and needs no
Accessibility: reel drives the page itself and draws the cursor into the video afterwards.

The recording is the page with square corners: no title bar, and none of the window's rounded corners with your
desktop showing in them. WebKit's window has no frame at all. Chromium's window is a little larger than the page, so
its corners are outside what is recorded; its thin edge can still show as a line along the page's left side.

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
