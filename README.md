<p align="center"><img src="docs/images/icon.png" alt="Last Call app icon" width="160"></p>

<h1 align="center">Last Call</h1>

Last Call is a macOS menu bar app that shows your Claude 5-hour session usage and weekly usage as percentages, with the time each one resets. The tick on each bar marks how much of the window has passed, so “Behind pace” means you’ve used less than an even share so far.

<p align="center"><img src="docs/images/screenshot.png" alt="Last Call’s popover open below its menu bar item: Current Session 10% used, resets in 47 min; This Week 36% used, resets Fri 3:00 AM; both behind pace" width="600"></p>

## Where the numbers come from

Last Call reads the Claude Code sign-in from the login Keychain (item “Claude Code-credentials”) by running `/usr/bin/security`, then requests `https://api.anthropic.com/api/oauth/usage` with that access token. When the token is within 5 minutes of expiring, Last Call refreshes it at `https://platform.claude.com/v1/oauth/token` and writes the new tokens back to the same Keychain item, so Claude Code stays signed in. Nothing is sent anywhere else, and tokens are never logged or shown.

It polls every 5 minutes (plus or minus 15 seconds), when the popover opens and the data is more than 60 seconds old, and after the Mac wakes. After an HTTP 429 the interval doubles, up to 30 minutes. While signed out it checks the Keychain every 60 seconds.

## Setup

Sign in to Claude Code once. In Terminal:

```
claude /login
```

If Last Call finds no sign-in, the popover shows “Sign in to Claude Code to see your limits.” with a Copy Sign-In Command button that puts `claude /login` on the pasteboard.

## Build

Requires macOS 26 and Xcode 26 or later.

```
Scripts/build-app.sh
```

This builds `dist/LastCall.app` and signs it ad hoc. `Build Last Call.command` does the same when double-clicked in Finder, then opens the app.

```
swift build
swift test
```

## Layout

- `Sources/LastCallKit`: credentials, token refresh, usage client, models, pace math, formatting, notification rules.
- `Sources/LastCallApp`: menu bar item, popover, Settings, About, notifications, App Intent.
- `Tests/LastCallKitTests`: JSON decoding, pace math, countdown formatting, token expiry, refresh flow, notification rules.

## License

Copyright © 2026 Daniel McCullum. Last Call is free software under the [GNU General Public License v3.0](LICENSE): you may use, change and share it, and anything you distribute that's built from it must be shared under the same license.
