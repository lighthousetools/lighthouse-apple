# Lighthouse for Mac and iOS

The native apps of [Lighthouse](https://github.com/lighthousetools/lighthouse) by Lighthouse Tools, a personal assistant
you run yourself. Both connect to your own server.

- **iOS:** today's overview, approvals, Claude Code sessions, agents, the Second Brain and settings.
- **Mac:** the web app in a native window, so it looks exactly like in the browser, plus a menu bar item that shows what
  waits for you and answers permission requests, notifications for new requests even while the window is closed, and
  native shortcuts. [docs/bridge.md](docs/bridge.md) describes how the window and the web app talk.

Both speak German and English. Choose the language in Settings or on the sign-in screen.

## On the Mac

| Shortcut | Action |
|---|---|
| ⌘K | Command palette |
| ⌘1 to ⌘9 | The first nine areas of the navigation |
| ⌘N | New note |
| ⌘R | Reload |
| ⌘, | Settings |
| ⌥⌘L | Quick panel for a note or a task, from anywhere |

The Mac window needs a server that delivers the web app (`paths.web` in `lighthouse.toml`). If the server cannot be
reached, the window says so and tries again by itself.

Requires Xcode 26 or later, and iOS 26 or macOS 26 on the device.

## Run on your own devices

You don't need the App Store.

```sh
cp Local.xcconfig.example Local.xcconfig   # enter your Apple team ID
open Lighthouse.xcodeproj
```

Choose the `LighthouseMac` scheme and run it, or connect your iPhone, enable Developer Mode on it, and run the
`Lighthouse` scheme. A free Apple ID works too, but such builds expire after seven days.

The apps accept plain HTTP only on the local network, for trying things out. Everything else needs HTTPS.

## Structure

| Path | Content |
|---|---|
| `Packages/LighthouseKit` | API client, Keychain storage and app state (`LighthouseKit`), shared SwiftUI views (`LighthouseUI`) |
| `Apps/iOS`, `Apps/Mac` | Thin app targets |
| `project.yml` | Source of the Xcode project. After changing it, run `xcodegen generate` with an empty team, so that yours stays out of the repository |

Tests run without a simulator:

```sh
cd Packages/LighthouseKit && swift test
```

## Not yet included

Push notifications need an Apple key on your server. Until then, the apps update live only while they run. Editing
agents and credentials happens in the web app. Widgets and the share extension for iOS are still open.

## License

[MIT](LICENSE)
