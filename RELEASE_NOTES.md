# Duotlet 0.2.0

The experimental GitHub package is ad-hoc signed, not notarized, and omits
Control Center. See [EXPERIMENTAL.md](EXPERIMENTAL.md) for installation and update
limitations. It is a prerelease and is not offered through stable update checks.

## What's new

- First-launch setup for Screen Recording access and optional anonymous analytics, available in English, Russian, and Simplified Chinese.
- The first 20° of a closing gesture stay clear, with filtering for very slow lid adjustments.
- Refined blur and dimming curves, with gradual blackout below 30°.
- Updated opening and reversal animations, retained presentation across sleep, and asynchronous rendering preparation.
- A custom, static Control Center icon without the unwanted press scaling on macOS 26+.
- Check for updates from Settings or the menu bar.
- Daily update notifications with a direct download from GitHub Releases.
- View the installed version, build number, and last update check in Settings.

## Compatibility

Requires macOS 14 or later and a MacBook with a compatible lid angle sensor. The effect uses Screen Recording permission and affects only the built-in display. Control Center support requires macOS 26 or later.

Physical lid movement and wake timing can vary by MacBook. Automated motion tests do not replace hardware verification.
