# PR Queue for macOS

A menu bar app for [gh-prq](https://github.com/daviddecorso/gh-prq), the macOS counterpart of the Plasma widget in this repo. The menu bar shows an icon with the number of PRs where it's your turn. Click it for the list, grouped by bucket, with a CI dot, the reason it's your turn, and how long it has been your turn. Click a PR to open it in the browser.

Needs macOS 14 (Sonoma) or later and gh-prq.

## Install

Download `PR-Queue-<version>.zip` from [Releases](https://github.com/lucasrossell/gh-prq-widget/releases), unzip it, and move **PR Queue.app** to Applications. It's signed and notarized, so it opens without a Gatekeeper warning. Turn on **Open at login** in its settings to keep it around.

## Settings

Open the app from the menu bar, then **Settings…** (⌘,).

- **Command**: default `gh prq --json --envelope`. It runs through your login shell (`zsh -l -c`), so `PATH` set in `~/.zprofile` applies, and `/opt/homebrew/bin` and `/usr/local/bin` are always added. Aliases and anything else from `~/.zshrc` aren't loaded. Extra gh-prq flags work: `gh prq --json --envelope --org acme`. To try it with made-up data: `cat /path/to/gh-prq-widget/docs/sample.json`.
- **Refresh every**: default 5 minutes. It also refreshes after the Mac wakes, and ⌘R in the panel refreshes now.
- **Show PRs waiting on someone else**: off by default.
- **Open a PR in the browser when clicked**: on by default. Right-click a PR for *Copy Link*.

## How it's built

A Swift package with two targets:

- `PRQueueCore`: Foundation only. It parses gh-prq's output (with or without `--envelope`), groups PRs into buckets, and runs the command. Its tests run on Linux too.
- `PRQueue`: the SwiftUI app (`MenuBarExtra` and a `Settings` window). Only built on macOS.

There's no Xcode project. `scripts/build-app.sh` wraps the SwiftPM binary in an `.app` bundle with `Info.plist`.

```sh
cd macos
swift test                    # core tests, macOS or Linux
swift run PRQueue             # run the app from source (macOS)
scripts/build-app.sh          # build/PR Queue.app, ad hoc signed
```

To run the tests on Linux without installing Swift:

```sh
docker run --rm -v "$PWD":/repo -w /repo/macos swift:5.10 swift test --scratch-path /tmp/build
```

## Releasing

Pushing a tag like `macos-v0.1.0` runs `.github/workflows/macos.yml` on a macOS runner. It tests, builds a universal binary, signs it with the Developer ID certificate, notarizes and staples it, and attaches the zip to a GitHub release. Pushes and PRs that touch `macos/` run the same build, unsigned, so a broken build shows up before a release.

```sh
git tag macos-v0.1.0 && git push origin macos-v0.1.0
```

### One-time setup

The workflow needs these repository secrets (*Settings → Secrets and variables → Actions*):

| Secret | What it is |
|---|---|
| `MACOS_CERT_P12_BASE64` | The **Developer ID Application** certificate and its private key, exported from Keychain Access as a `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | The password chosen when exporting the `.p12` |
| `APPLE_ID` | The Apple ID email of a member of the developer team |
| `APPLE_TEAM_ID` | The team ID from [developer.apple.com/account](https://developer.apple.com/account) → Membership |
| `APPLE_APP_PASSWORD` | An app-specific password for that Apple ID, made at [account.apple.com](https://account.apple.com) → Sign-In and Security |

Only the team's **Account Holder** can create a Developer ID Application certificate (developer.apple.com → Certificates → +). Anyone on the team can notarize with it once it exists.

To sign and notarize locally instead, have the certificate in your keychain and run:

```sh
VERSION=0.1.0 SIGN_IDENTITY="Developer ID Application" scripts/build-app.sh
VERSION=0.1.0 APPLE_ID=… APPLE_TEAM_ID=… APPLE_APP_PASSWORD=… scripts/notarize.sh
```
