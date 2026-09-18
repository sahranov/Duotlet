# Duotlet

## Download

**[Releases and downloads](https://github.com/sahranov/Duotlet/releases)**

**Duotlet 0.2.0 — Experimental** · No paid Apple developer account is needed to download this build.

This prerelease is ad-hoc signed and is **not notarized by Apple**. Read the [installation instructions and limitations](EXPERIMENTAL.md) before installing.

| Download | Format |
| --- | --- |
| [Duotlet 0.2.0 for macOS](https://github.com/sahranov/Duotlet/releases/download/v0.2.0-experimental.1/Duotlet-0.2.0.dmg) | DMG installer |
| [Duotlet 0.2.0 ZIP](https://github.com/sahranov/Duotlet/releases/download/v0.2.0-experimental.1/Duotlet-0.2.0.zip) | ZIP archive |

Both packages include Apple Silicon and Intel binaries. Requires **macOS 14+** and a MacBook with a compatible lid angle sensor. This experimental package uses the menu bar and Settings; it does not include Control Center support.

For a first installation, open the DMG and drag **Duotlet** into **Applications**, or extract the ZIP. If macOS blocks the unidentified developer, use **System Settings → Privacy & Security → Open Anyway** for Duotlet. On first launch, follow setup to allow Screen Recording and choose whether to share anonymous analytics.

**Do not replace an existing Apple-signed Duotlet installation with this experimental build.** Ad-hoc updates may invalidate Screen Recording authorization. This prerelease is not offered through the stable update checker.

## About

Duotlet adds a live depth, blur, and dimming effect while closing a compatible MacBook lid.

- A compact menu offers **Turn effect on/off**, **Settings…**, and **Quit Duotlet**.
- Settings control the effect on/off switch, login launch, Dock visibility, menu bar visibility, angle display, and language.
- English is the default. Russian and Simplified Chinese are included.
- Settings and the menu offer **Check for Updates…**. Daily checks notify users about new GitHub releases; installation is manual. See [RELEASING.md](RELEASING.md) for the release process.
- The first 20° of a closing gesture stay clear; very slow lid adjustments are ignored.
- Live rendering is always enabled. Blur increases with closing travel and lid angle; dimming begins below 90°.
- Below 30°, an additional whole-screen fade progressively reaches black at 0°.
- Apple-signed native builds on macOS 26+ include a Control Center switch. The experimental download omits this extension.

The effect requires macOS 14+ and a compatible built-in lid angle sensor. It affects only the built-in display and requires Screen Recording permission. Reopening Duotlet from Applications or Spotlight always opens Settings, even if both icons are hidden. Closing Settings leaves the effect running.

## Build and run locally

Use an SDK for macOS 26 or newer. Full Xcode 26+ is recommended.

```sh
./build.sh
```

This packages `output/Duotlet-build.zip` for compile verification. It does not install or launch it. `--universal` includes both Apple Silicon and Intel. Optional `SWIFT`, `SWIFTC`, `SDKROOT`, and `DUOTLET_BUILD_DIR` select an alternate toolchain and build directory.

`--install` and `--run` require `SIGN_IDENTITY` for a real Apple Development or Developer ID identity. Before replacing `/Applications/Duotlet.app` (or `DUOTLET_BUNDLE`), the installer verifies that the candidate satisfies the existing app's designated requirement and has the same bundle identifier. A mismatch stops installation and leaves the existing app untouched. Backups are kept under `output/app-backups/`.

Never install or launch an ad-hoc rebuild over an app with Screen Recording authorization. Its permission identity changes with the code hash. Keep the signing team and bundle identifier stable across updates; users should not remove and re-add privacy permissions after ordinary updates. Transitioning from historical ad-hoc builds is a separate one-time migration, not an ordinary update. See `AGENTS.md` for the mandatory installation rule.

Settings and the menu explicitly show when the effect is paused for missing screen access. The **Allow Screen Recording** button starts the system permission flow. Background checks never prompt; access is rechecked when returning to the app. User authorization cannot be granted by Duotlet itself.

The command-line build is a local development build. Its ad-hoc signature cannot authorize the shared App Group used by the sandboxed Control Center extension on current macOS. Registration alone does not prove that the control works. Use the native Xcode project and a real development/distribution identity to validate that feature.

## Native distribution build

Open `Duotlet.xcodeproj` in Xcode 26+ and select your development team for both Duotlet and DuotletControl. The app embeds the extension; users do not install shortcuts or helper scripts. Xcode generates the App Intents metadata used by the system.

The public bundle IDs are `app.duotlet.Duotlet` and `app.duotlet.Duotlet.Control`; register or customize both before distribution. The public app migrates preferences from the earlier local bundle ID.

Both targets must use the same `DUOTLET_APP_GROUP` and valid App Group entitlements. For a Mac-only build, the archive script defaults to `<TEAM_ID>.app.duotlet.shared`. Alternatively, register a `group.` identifier and provision it for both targets.

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/archive.sh
```

Use the Xcode Organizer to export for Developer ID or App Store distribution. Signing certificates, provisioning, store metadata, privacy declarations, and testing the lid sensor and screen capture under App Sandbox remain release prerequisites. The native project enables sandboxing, USB/HID device access, and outgoing networking for the existing analytics integration. App Store approval is not assumed.

`./scripts/generate-xcode-project.py` regenerates the checked-in project when source files are added. The release workflow builds both targets through Xcode and signs the extension before signing the containing app.

## Verification

```sh
bash Tests/run-regressions.sh
python3 Tests/test_install_identity.py
bash Tests/run-render-checks.sh
swift test
python3 -m unittest discover -s Tests -p 'test_release*.py'
bash Tests/run-update-checks.sh
```

The standalone checks cover closing/opening motion, lid adjustments, reversals, blur, wake continuity, the final 30° blackout, onboarding, and analytics consent. `swift test` needs full Xcode's Swift Testing module; the Command Line Tools package does not include it.

For live timing checks, launch with `--profile-animation` and run `Tests/ProfilePreview.swift`. Real first-open and delayed-open sleep cycles still need physical verification; a scripted resume does not reproduce all hardware wake timing.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for the license and third-party attribution.
