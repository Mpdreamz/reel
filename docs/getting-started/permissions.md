---
description: "reel needs Screen Recording to record and Accessibility to click and type. reel doctor reports both."
---

# Permissions

macOS asks before any program records the screen or controls another app. reel needs:

| Permission | For | Needed by |
|---|---|---|
| Screen Recording | Capturing the window and its sound | Every tape |
| Accessibility | Finding buttons, clicking, typing, pressing keys and scrolling | App tapes that drive the app (`Click`, `Type`, `Key`, `Scroll`, `Wait`, `Set Size`, a zoom on an element) |

Both are granted to the terminal reel runs in, not to reel itself: if you run reel from Ghostty, Ghostty gets them.
The first recording asks; you can also add the terminal yourself in **System Settings → Privacy & Security**.

`reel doctor` reports what is granted, without asking for anything:

```
$ reel doctor
Screen Recording: granted
Accessibility:    granted
Web pages:        WebKit, built in (Set Browser chromium for Chromium)
Chromium:         Google Chrome 141.0 at /Applications/Google Chrome.app
```

A web tape needs only Screen Recording: reel drives the page itself, in WebKit or over Chromium's DevTools, without
Accessibility.

## While a tape plays

An app tape uses the real mouse and keyboard, so the demo shows a real cursor and real clicks. Leave the Mac alone
until it finishes. Before every step reel checks the app is still in front; if it isn't, reel brings it back once,
and otherwise stops the tape, so typing can never land in another app.

A web tape leaves your mouse and keyboard alone: reel draws the cursor into the video afterwards.
