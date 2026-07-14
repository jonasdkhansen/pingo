<!-- markdownlint-disable MD023 MD033 MD041 -->
<div align="center">
  <img src="assets/pingo-app-icon.png" width="220" alt="Pingo app icon">

  # Pingo

  **A tiny network monitor for your Mac menu bar.**

  Know when your connection drops, when it returns, and how it has behaved at a glance.

  [![macOS 11+](https://img.shields.io/badge/macOS-11%2B-111111?style=flat-square&logo=apple&logoColor=white)](https://github.com/jonasdkhansen/pingo/releases/latest)
  [![Swift](https://img.shields.io/badge/Swift-AppKit-F05138?style=flat-square&logo=swift&logoColor=white)](main.swift)
  [![Latest release](https://img.shields.io/github/v/release/jonasdkhansen/pingo?style=flat-square&color=2ea44f)](https://github.com/jonasdkhansen/pingo/releases/latest)

  [**Download Pingo for macOS**](https://github.com/jonasdkhansen/pingo/releases/download/v1.1.0/Pingo-1.1.0-macos.zip)
</div>

---

Pingo lives quietly in the menu bar with no Dock icon and no main window. It checks two independent public DNS endpoints and changes state only when both stop responding, helping avoid false alarms caused by a single provider.

## At a glance

| | |
| --- | --- |
| **Instant status** | A green or red menu bar indicator shows whether the internet is responding. |
| **Native alerts** | Get notified when the connection drops and when it returns, including the outage duration. |
| **Live history** | See session uptime, total checks, failures, and recent connection results. |
| **Auto-Fix Wi-Fi** | Reconnect the active network without turning the Wi-Fi radio off. |
| **Flexible checks** | Choose any interval from 1 to 60 seconds or run an immediate check. |
| **Built for macOS** | A lightweight Swift and AppKit app with native controls, SF Symbols, and no runtime dependencies. |

## How it works

Pingo sends one packet to both `1.1.1.1` (Cloudflare) and `8.8.8.8` (Google) with a three-second timeout. If either endpoint replies, the connection is considered online.

When the connection changes state, Pingo responds immediately:

- **Connection lost:** the antenna turns red and a notification appears.
- **Connection restored:** the indicator returns to green and the notification includes how long the outage lasted.
- **Monitoring paused:** checks stop completely and the menu bar icon dims.

Open Pingo from the menu bar to see the current status, recent history, session statistics, check interval, and quick controls. Settings persist across launches.

## Auto-Fix Wi-Fi

Auto-Fix is optional and disabled by default. When enabled, Pingo remembers the active Wi-Fi network, disconnects from it, and explicitly rejoins the same network. The Wi-Fi radio stays powered on throughout the process.

Pingo checks that the network and saved credentials are available before disconnecting. A one-minute cooldown prevents repeated reconnect attempts during a wider outage.

> [!NOTE]
> macOS requires Location access to reveal the current Wi-Fi network name. Pingo requests this permission only when Auto-Fix is enabled and uses the network name only to reconnect that same network.

## Install

1. Download [Pingo-1.1.0-macos.zip](https://github.com/jonasdkhansen/pingo/releases/download/v1.1.0/Pingo-1.1.0-macos.zip).
2. Extract the archive and move `Pingo.app` to your Applications folder.
3. Open Pingo. Its antenna indicator will appear in the menu bar.

Pingo is ad-hoc signed. On first launch, macOS may ask you to approve it under **System Settings > Privacy & Security**.

### Start at login

Open **System Settings > General > Login Items**, select **+**, and add `Pingo.app`.

### Notifications

Notifications use macOS's script notification channel and appear as **Script Editor** under **System Settings > Notifications**. Allow notifications there if Pingo alerts are not visible.

## Build from source

You need macOS 11 or newer and Xcode Command Line Tools:

```sh
xcode-select --install
git clone https://github.com/jonasdkhansen/pingo.git
cd pingo
./build.sh
open Pingo.app
```

The build script renders the app icon, compiles the Swift source, assembles the app bundle, and applies an ad-hoc signature.

## Customize

Pingo intentionally keeps its implementation small. The complete app lives in [main.swift](main.swift).

- Edit `pingHosts` to change the endpoints. Pingo reports an outage only when every configured host fails.
- Edit `setIcon(state:)` to use different SF Symbols in the menu bar.
- Run `./build.sh && open Pingo.app` after making changes.

## Project layout

| Path | Purpose |
| --- | --- |
| `main.swift` | Complete Swift and AppKit application |
| `Info.plist` | Bundle metadata, version, permissions, and menu bar app configuration |
| `build.sh` | Icon rendering, compilation, app assembly, and signing |
| `assets/pingo.png` | Original Pingo artwork |
| `assets/pingo-app-icon.png` | Rendered macOS app icon master |
| `assets/render-app-icon.swift` | Icon renderer |
| `assets/Pingo.icns` | macOS icon bundle |

## Test an outage

Turn Wi-Fi off for about 20 seconds. Pingo should report that the internet is down, then show a recovery notification after Wi-Fi is restored.

---

<div align="center">
  <sub>Small, native, and focused on one job.</sub>
</div>
