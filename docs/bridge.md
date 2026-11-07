# Mac app bridge

The main window of the Mac app shows the web app in a `WKWebView`. The menu bar item, the quick note, notifications,
shortcuts and the Keychain stay native. This page describes how the two sides talk, so that the web app can adopt the
bridge. Everything here is optional for the web app: it works unchanged in the window, and in a browser the bridge
simply does not exist.

## Detecting the app

```ts
const bridge = (window as any).webkit?.messageHandlers?.lighthouse;
if (bridge) {
  // Running in the Mac app.
}
```

The app also sets `data-native-shell="mac"` on `<html>` once the page is parsed, and two CSS variables on `:root`:

| Variable | Value | Meaning |
|---|---|---|
| `--native-titlebar-height` | `28px` | Height of the transparent title bar strip over the page |
| `--native-controls-width` | `78px` | Width the window buttons take at the top left |

The web app uses them to keep its rail and sidebar clear of the window buttons and the top strip free for dragging. For
the older layout of the web app, the app also adds `padding-top: 46px` to `.layout > .sidebar`; the current layout does
not match that rule.

## Messages from the web app

Send a plain object with `postMessage`. Every message has a `type`. An optional `v` names the protocol version; the app
speaks version `1` and refuses messages with a higher one. Unknown types and malformed messages are ignored. Messages
count only from the main frame on the server's own origin.

```ts
bridge.postMessage({ type: "notify", id: "approval:<id>", title: "Send the weekly report?", route: "#ready/approval:<id>" });
```

| `type` | Fields | Effect |
|---|---|---|
| `ready` | `v?` | The web app has adopted the bridge. Send it once after start. |
| `notify` | `title` (required, up to 200 characters), `body?` (up to 1000), `route?` (a hash such as `#ready/approval:<id>`), `id?` | Shows a native notification. A click brings the window to the front at `route`. The same `id` replaces an earlier notification. |
| `badge` | `count` (whole number, clamped to 0 to 9999) | Sets the number on the Dock icon; `0` removes it. Once the web app sends a badge, it wins over the app's own count, which is the ready total as well. |
| `openExternal` | `url` (`http`, `https` or `mailto`) | Opens the link in the default browser. |

The web view never leaves the server's origin. Links to other sites, `target="_blank"` and `window.open` open in the
default browser anyway; `openExternal` only makes the intent explicit.

## Commands from the app

Menu items and shortcuts reach the web app as a cancelable event on `window`:

```ts
addEventListener("lighthouse:command", (event) => {
  const { command } = (event as CustomEvent<{ command: string }>).detail;
  if (command === "palette") {
    event.preventDefault();
    openPalette();
  }
});
```

| `command` | Shortcut | Fallback when the event is not canceled |
|---|---|---|
| `palette` | ⌘K | A synthetic `keydown` of ⌘K on `window` |
| `newNote` | ⌘N | `location.hash = "#brain/new"` |

Routes do not need an event. The app sets `location.hash`, as the web app's own router expects:

| Shortcut | Route |
|---|---|
| ⌘1 to ⌘9 | The first nine entries of the web app's navigation: `#ready`, `#tasks`, `#brief`, `#recap`, `#sessions`, `#alerts`, `#brain`, `#automations`, `#agents` |
| Lighthouse > More | `#log`, `#connections`, `#rules`, `#me`, `#settings` |
| ⌘, | `#settings` |
| ⌘R | Reloads the page |

Routes are written like the web app's `href`: `#view/` followed by the parameter through `encodeURIComponent`. The app
reads hashes like the web app's `parseRoute`, including the old names `#today` and `#approvals` (both `#ready`),
`#weekly` (`#recap`) and `#claude` (`#sessions`), so a restored route from an older version still works.

The menu bar item, the quick panel and notifications open the window at these routes:

| What | Route |
|---|---|
| An item of the ready feed | `#ready/<kind>:<id>`, for example `#ready/approval:<id>` |
| Several ready items | `#ready` |
| A critical alert | `#alerts/<id>` |
| A task | `#tasks/<id>` |

## Notifications

The menu bar item keeps its own connection to `GET /events`, also while the window is closed. On `changed`,
`ready.changed`, `alert.raised`, `alerts.changed`, `tasks.changed`, `sessions.changed`, `run.waiting` and `run.finished`
it reloads `GET /ready`, `GET /alerts/counts` and the active alerts, shows the ready count and open critical alerts, and
announces what is new:

- Ready items, with the web app's key `kind:id` as the notification ID. While the web app is loaded and has sent
  `ready`, it announces them itself through `notify` with the same keys, and the app stays quiet about them.
- Critical alerts, always from the app, with the ID `alert:<id>`.

Servers without `GET /ready` fall back to approvals and permission requests.

## Sign-in

The app keeps the device token in the Keychain. Before any script of the page runs, a script of the app writes it to
`localStorage["lighthouse.token"]`, together with the chosen language in `localStorage["lighthouse.language"]`. The web
view stores nothing on disk, so the token is handed over again with each load. This script runs in a content world of its
own: the page cannot see it or send its messages.

That script also watches the two keys. When the web app removes the token, because the owner signed out or the server
refused it, the app signs out as well and shows its native sign-in. A language chosen in the web app becomes the app's
language.

## Window

The app remembers the last route and the window size. Where the page has nothing to click in the top strip, a drag moves
the window and a double click zooms it, like a title bar.
