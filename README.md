<p align="center"><img src="site/logo.svg" width="96" alt="Jauge"></p>

<h1 align="center">Jauge</h1>

<p align="center">Keeps your MacBook battery at the level you choose: charge limit, discharge while plugged in, calibration, heat protection, scheduling. A menu bar app for Apple silicon Macs.</p>

<p align="center"><a href="https://vlor999.github.io/jauge/">Website</a> · <a href="https://github.com/Vlor999/jauge/releases/latest">Download</a> · <code>brew install --cask vlor999/tap/jauge</code></p>

## Features

- Charge limit from 20 to 100%
- Discharge while plugged in, manual or automatic
- Idle range: recharge only below a threshold
- Calibration cycle (100 → 10 → 100%, 1 h rest, back to the limit)
- Heat protection with 5-minute windows
- Charge to 100% once, until unplugged
- Power flow (adapter, battery, Mac) with a weak-adapter warning
- Schedule: limit, calibration, full charge, pause, discharge, Low Power Mode; missed tasks on wake; history
- MagSafe LED colors
- Keep awake until the limit, freeze the level during sleep
- Shortcuts actions and a CLI (`jaugectl`)
- French UI

## Install

- Download the `.dmg` from the [website](https://vlor999.github.io/jauge/) or the [releases](https://github.com/Vlor999/jauge/releases), or `brew install --cask vlor999/tap/jauge`.
- Signed and notarized by Apple. Drag Jauge to Applications and open it.
- On first launch, allow Jauge's background service in System Settings > General > Login Items. That root service is what talks to the battery controller.
- Updates install on their own (Sparkle, checked every 6 hours, EdDSA-signed).

Command line: `jaugectl status`, `jaugectl limit 70`, `jaugectl discharge on`… With Homebrew it is on your `PATH`; otherwise it lives in `/Applications/Jauge.app/Contents/MacOS/jaugectl`.

## How it works

| Part | Role |
|---|---|
| `App/` | SwiftUI menu bar app, settings, Shortcuts actions, Sparkle updater |
| `Daemon/` | `jaugectl daemon`: root service registered with `SMAppService`, owns all charging logic, talks to the SMC and to macOS's charge limit |
| `Shared/` | Model, charging policy (pure, tested by `make check`), socket client |

- macOS 26+: Apple's Manual Charge Limit (80–100%) through the private `PowerUI` framework; below 80%, the SMC discharge key `CHIE` alternates battery and adapter.
- Older firmware: SMC keys `CHTE` or `CH0B`/`CH0C` stop charging, `CHIE`/`CH0I` force discharge.
- The app and the CLI talk to the service over `/var/run/jauge.sock` (root:admin, 0660).

## Build

```sh
brew install xcodegen
make check   # charging policy self-test
make         # build/Build/Products/Release/Jauge.app (Developer ID identity required)
```

Releases: bump `VERSION`, push to `main`. See [docs/release.md](docs/release.md).

## Privacy

No account, no telemetry. The only network request is the update check to GitHub.

## Disclaimer

Jauge is an independent project. It is not affiliated with or endorsed by Apple, or by the makers of any other battery tool. It uses undocumented macOS interfaces that may change with any update.

## License

MIT
