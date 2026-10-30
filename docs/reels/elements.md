---
description: "How a reel names what to click, wait for, scroll over and zoom on."
---

# Elements

`Click`, `Wait`, `Scroll` and `Zoom` take an element:

| Write | Means |
|---|---|
| `"Save"` | The element whose title, description or value is exactly `Save`. Quoted is always a label. |
| `Save` | The same, unquoted, for a single word. |
| `#save-button` | The element whose accessibility identifier is `save-button`. |
| `@120,80` | A point, in points from the window's top left. A last resort: it breaks when the layout moves. |

In an app, reel searches the app's windows breadth first, so sheets and popovers count, and takes the shallowest
match. The element must be on a screen. `Click` waits for it for up to `WaitTimeout` (10 seconds unless set).

Identifiers are the sturdiest: a label changes with the language and the copy. In SwiftUI, give a view one with
`.accessibilityIdentifier("play")`.

## Web pages

On a page, an element is found by JavaScript in the page:

| Write | Means |
|---|---|
| `"Sign in"` | An element whose accessible name, placeholder, title, alt text, button value or text is exactly `Sign in`. Controls come before other elements, then the smallest. |
| `#email` | The element with that `id`, or that `data-testid`. |
| `css:.submit` | The first visible match of a CSS selector. Quote it after the colon when it has spaces: `css:"form button"`. |

A click scrolls its element into the middle of the page first.

## Markers

`Wait [play]` is not an element: it waits for narration to reach a `[play]` marker. See
[Narration](../demos/narration.md).
