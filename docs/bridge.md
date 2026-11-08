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

The app also sets attributes on `<html>` once the page is parsed:

| Attribute | Meaning |
|---|---|
| `data-native-shell="mac"` | The page runs in the Mac window |
| `data-native-vibrancy="1"` | The window draws the macOS sidebar material behind the page |

And two CSS variables on `:root`:

| Variable | Value | Meaning |
|---|---|---|
| `--native-titlebar-height` | `28px` | Height of the transparent title bar strip over the page |
| `--native-controls-width` | `78px` | Width the window buttons take at the top left |

The web app uses them to keep its rail and sidebar clear of the window buttons and the top strip free for dragging. For
the older layout of the web app, the app also adds `padding-top: 46px` to `.layout > .sidebar`; the current layout does
not match that rule.

## Vibrancy

The web view draws no background of its own. Behind it the window has an `NSVisualEffectView` with the sidebar material,
blended with what lies behind the window, so the desktop shows through like in the sidebar of Finder or Mail. It follows
light and dark mode and dims while the window is inactive.

With `data-native-vibrancy="1"` the web app should leave its shell background transparent: no sky, gradient or opaque
fill behind the rail and the sidebar, so the material shows there. The content stays a floating, rounded, opaque panel.
Every pixel the page paints covers the material, so translucent fills tint it rather than replace it.

## Organizations and the session pill

In the Mac window the web app hides its top menu bar, and with it the company selector and the session pill. The web app
shows both in the sidebar header instead. The app adds a native **Company** menu to the menu bar as well: it lists
"All companies" and every organization from `GET /organizations`, with a check mark on the one the web app shows.

- A choice in the menu reaches the web app as the command `org` (see below). The web app switches and confirms with the
  `org` message.
- Whenever the organization changes in the web app, it sends `org`, so the menu follows.
- The app remembers the choice and writes it to `localStorage["lighthouse.org"]` before each load, because the web view
  stores nothing between launches.

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
| `org` | `id` (an organization ID of lowercase letters, digits and dashes; `""`, `null` or missing for all) | The organization the web app shows now. Send it at start and on every change. |

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
| `org` | Company menu | Writes `localStorage["lighthouse.org"]` and reloads |

The `org` command carries the organization in the detail: `{ command: "org", type: "org", id: "<id or empty for all>" }`.

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

The app signs in natively, with the server address, the email (only once the server has more than one user, as
`GET /auth/status` tells), the password and a name for the device. It keeps one device token per server, user and
tenant in the Keychain. Before any script of the page runs, a script of the app writes the token of the current tenant
to `localStorage["lighthouse.token"]`, together with the chosen language in `localStorage["lighthouse.language"]`. The
web view stores nothing on disk, so the token is handed over again with each load. This script runs in a content world
of its own: the page cannot see it or send its messages.

That script also writes the remembered organization to `localStorage["lighthouse.org"]`, and watches the token and
language keys:

- When the web app removes the token, because the person signed out or the server refused it, the app signs out of
  every tenant of that user on this server, revokes the kept tokens and shows its native sign-in.
- When the web app holds another token, because it switched tenants itself, the app asks `GET /me` with it and adopts
  it for the tenant `/me` names. The page keeps running. Since the web app signs out the token it replaced, a token the
  server refuses is first looked for in the web app before the app signs out.
- A language chosen in the web app becomes the app's language.

Accounts are created in the web app: on a server with `signup = "open"` the sign-in links to `#/signup` in the
browser, and with `signup = "invite"` it explains that the link of the invitation sets up the account.

## Tenants

The menu bar window and the **Lighthouse** menu name the signed-in person, the tenant and the role, and switch to the
user's other tenants from `GET /tenants`. A switch reuses the token kept for that tenant while `GET /me` accepts it, and
otherwise asks `POST /tenants/{id}/switch` for one. The token of the tenant left stays in the Keychain for the way back.
The web app then loads anew with the new token, without the organization of the old tenant, and live updates and
notifications start over, so what already waits in the new tenant is not announced as new.

A request the role does not allow (403) shows the server's reason and keeps the sign-in.

## Window

The app remembers the last route and the window size. Where the page has nothing to click in the top strip, a drag moves
the window and a double click zooms it, like a title bar.
