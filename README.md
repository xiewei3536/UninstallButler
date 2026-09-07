<div align="center">

<img src="docs/icon.png" width="128" alt="Uninstall Butler icon">

# Uninstall Butler

**A thorough, careful uninstaller for the Mac — finds every file an app leaves behind and removes it cleanly.**

**English** | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md)

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Architecture](https://img.shields.io/badge/Intel%20%7C%20Apple%20Silicon-Universal-8A2BE2)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

<img src="docs/screenshot.png" width="860" alt="Uninstall Butler main window">

</div>

---

## Why

Dragging an app to the Trash removes the app — and leaves behind its preferences, caches, support files, sandbox containers, background agents, install receipts and more. Over the years those leftovers add up to gigabytes. Uninstall Butler finds all of it, shows you exactly what it found and why, and removes it in one go.

## Features

- 🔍 **Truly thorough scan** — for each app it checks 40+ locations in both `~/Library` and `/Library`: Application Support, Preferences (incl. ByHost), Caches, Containers, Group Containers, Saved Application State, HTTPStorages / WebKit / Cookies, Logs, crash reports, LaunchAgents, LaunchDaemons, PrivilegedHelperTools, `pkgutil` receipts, Quick Look / Spotlight / audio plug-ins, Application Scripts, recent-documents lists, `/usr/local/bin` command-line shortcuts, and the per-user `/var/folders` cache & temp directories
- 🎯 **Precise attribution, not guesswork** — matches by bundle ID (main app *and* every embedded helper, XPC service, extension and privileged tool), by the app's code-signing entitlements (App Groups, Team ID), by launchd plists that point into the app, by symlinks into the bundle and by sandbox-container metadata. Name matching is used only as a clearly labelled fallback, and never when two installed apps share a name
- 🛡 **Knows what is shared** — Group Containers used by another app from the same developer, helpers embedded in several apps (Office, Google updaters…) are flagged *Also used by …* and left unticked; when an app is the developer's only app on your Mac, its shared updater agents are included and labelled *Same developer*
- ✨ **Leftovers scanner** — finds files from apps you deleted long ago (reverse-DNS names that no installed app, plug-in, input method, background service or Launch Services entry claims), sorted into *Safe to remove* and *Check first*
- 🧹 **Clean removal sequence** — quits the app and its helpers, unloads its login agents (`launchctl bootout`), moves everything to the Trash (or deletes permanently), forgets package receipts, prunes emptied vendor folders. System-level items are handled with a single administrator prompt
- 🧭 **Smart lists** — Rarely used, Large apps, Intel-only (Rosetta), App Store, Running; sort by name, size, last-used or date added; every app shows its architecture badge (Universal / Intel / Apple Silicon)
- 👐 **Human-first UI** — every item shows its path, size and *why* it was matched; a *Keep settings & data* switch for reinstalls; hover hints explain each category in plain language; batch uninstall by multi-selecting apps
- 🔒 **Safe by design** — a hard path allow-list means nothing outside the known Library / Applications / receipt locations can ever be touched, and root folders themselves are never deleted. SIP-protected apps are shown as locked. Defaults to the Trash, so everything is recoverable
- 🌐 **Trilingual** — English, 繁體中文, 简体中文; switch instantly in-app
- 🚀 **Universal binary** — native on Intel and Apple Silicon, macOS 13 Ventura or later, ~5 MB, no dependencies, nothing leaves your Mac

## Install

1. Download `UninstallButler.dmg` from the latest release
2. Drag **Uninstall Butler** into **Applications**
3. First launch: **right-click the app → Open** (it is not notarized, so Gatekeeper asks once)
4. Recommended: grant **Full Disk Access** (System Settings → Privacy & Security) so the butler can also check protected folders such as Cookies and container metadata. The app works without it, just slightly less thoroughly

## How the matching works

| Signal | Example | Confidence |
| --- | --- | --- |
| Bundle ID of the app or one of its embedded helpers | `~/Library/Preferences/com.google.Chrome.plist`, `~/Library/Containers/com.microsoft.Word.widgetextension` | High |
| launchd plist whose program lives inside the app | `~/Library/LaunchAgents/…` → `/Applications/Foo.app/Contents/MacOS/agent` | High |
| App Group / Team ID from the code signature | `~/Library/Group Containers/UBF8T346G9.Office` | High, flagged if shared |
| Sandbox container metadata pointing at the app | `~/Library/Containers/LINE.AudioService` | High (needs Full Disk Access) |
| Symlink into the bundle | `/usr/local/bin/code` | High |
| Vendor folder + product name | `~/Library/Application Support/Google/Chrome` | High |
| Developer prefix, when this is the developer's only app | `~/Library/LaunchAgents/com.google.keystone.agent.plist` | Labelled *Same developer* |
| Plain name | `~/Library/Logs/Spotify` | Labelled *Matched by name only* |

If another installed app has a *longer* matching bundle ID (Chrome vs. Chrome Canary), the item is attributed to that app instead.

## Build from source

Requires only the Command Line Tools (no Xcode needed):

```bash
git clone https://github.com/xiewei3536/UninstallButler.git
cd UninstallButler
./build.sh            # → dist/UninstallButler.app + dist/UninstallButler.dmg (universal)
```

Developer hooks (nothing is ever deleted by these):

```bash
UNINSTALLBUTLER_SELFTEST=1 UNINSTALLBUTLER_SELFTEST_APP="Google Chrome" .build/debug/UninstallButler
UNINSTALLBUTLER_SNAPSHOT=/tmp/ub.png UNINSTALLBUTLER_LANG=zh-Hant .build/debug/UninstallButler
UNINSTALLBUTLER_DRYRUN=1 .build/debug/UninstallButler     # full UI, removal is simulated
swift test                                                # unit tests (needs Xcode's XCTest)
```

## License

MIT
