# Duotlet 0.2.0 — Experimental

This is an experimental, ad-hoc signed build. It is not signed with an Apple
Developer ID certificate and has not been notarized by Apple.

## Install and open

Requires macOS 14 or later and a MacBook with a compatible lid angle sensor.
Both Apple Silicon and Intel binaries are included.

For a first installation, open the DMG and drag Duotlet to Applications, or
extract the ZIP and move Duotlet there. Launch Duotlet. If macOS blocks it because
the developer cannot be verified, open System Settings → Privacy & Security and
use Open Anyway for Duotlet, then confirm. This is an exception for this app;
you do not need to disable Gatekeeper system-wide.

Apple's instructions: https://support.apple.com/102445

Follow Duotlet's setup to grant Screen Recording access and choose whether to
share anonymous analytics. The effect only covers the built-in display.

## Limitations

- Control Center support is not included. Use the menu bar or Settings.
- This prerelease is not offered by the stable update checker.
- Ad-hoc rebuilds change signing identity. Screen Recording authorization may
  not survive replacement with another build. Do not replace an existing
  Apple-signed, authorized Duotlet installation with this package.
- Hardware lid movement, wake timing, and first launch on another Mac have not
  been verified for this experimental package. Compilation and regression tests
  do not establish those results.

Source code and release notes: https://github.com/sahranov/Duotlet
