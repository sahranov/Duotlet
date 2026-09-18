# Mandatory installation rule

**НИКОГДА НЕ ПЕРЕЗАПИСЫВАЙ УСТАНОВЛЕННЫЙ DUOTLET СБОРКОЙ С AD-HOC ПОДПИСЬЮ. ЭТО ЛОМАЕТ ВЫДАННЫЕ macOS РАЗРЕШЕНИЯ ПРИ КАЖДОЙ ПЕРЕСБОРКЕ.**

**НЕ ПРЕДЛАГАЙ УДАЛЯТЬ И ЗАНОВО ДОБАВЛЯТЬ РАЗРЕШЕНИЕ НА ЗАПИСЬ ЭКРАНА КАК ОБЫЧНЫЙ ШАГ ОБНОВЛЕНИЯ. НЕ СБРАСЫВАЙ TCC И НЕ МЕНЯЙ РАЗРЕШЕНИЯ, ЧТОБЫ КОМПЕНСИРОВАТЬ НЕПРАВИЛЬНУЮ ПОДПИСЬ.**

**ОБЕЩАНИЕ «БОЛЬШЕ ТАК НЕ ДЕЛАТЬ» НЕ ЗАМЕНЯЕТ ТЕХНИЧЕСКУЮ ПРОВЕРКУ. НЕ ОБХОДИ ЗАЩИТУ УСТАНОВКИ ПРЯМЫМ КОПИРОВАНИЕМ, ПЕРЕИМЕНОВАНИЕМ, ПЕРЕПОДПИСЫВАНИЕМ ИЛИ ОСЛАБЛЕНИЕМ CODE REQUIREMENTS.**

- Default `./build.sh` only packages `output/Duotlet-build.zip`. Do not launch the ad-hoc artifact under the installed app's identity.
- Installation requires a real Apple signing identity and a successful `scripts/verify-install-identity.py` check against the existing installation. Keep bundle identifier and signing team consistent across updates.
- Before replacing an installed build, verify the new build satisfies the old build's designated requirement. Successful compilation or ordinary signature verification alone is insufficient.
- If the required signing identity is unavailable or continuity fails, finish compilation/tests in the workspace and report the signing blocker. Leave the installed app and its permissions untouched.
- Stable release workflows must fail closed when Developer ID signing is unavailable. Do not silently fall back to ad-hoc signing or offer ad-hoc builds through stable update downloads.
- On 2026-09-18 the user explicitly approved a public experimental release without Apple signing or notarization. Package it through `scripts/package-experimental.sh`, label it as a GitHub prerelease, and explain Gatekeeper, Screen Recording update limitations, and the absence of Control Center support. This exception permits publishing archives only; it does not permit installing or launching an ad-hoc build over the user's installed app, changing TCC, or weakening installation continuity checks.
- Moving from a historical ad-hoc identity to a proper release identity is a separate, explicitly planned one-time migration; never silently perform it during a UI fix or ordinary update.
- Do not claim the installed app or screen-capture effect is fixed merely because the staged build or regression tests pass. State what remains unverified.

This rule records repeated permission breakage during local installs, reported by the user on 2026-09-18. Preserve it across future tasks and summaries.

**РАБОТАЙ ТОЛЬКО С ОДНОЙ УСТАНОВЛЕННОЙ СБОРКОЙ: `/Applications/Duotlet.app`. НЕ ОСТАВЛЯЙ ДУБЛИ `.app` В ПРОЕКТЕ, ВРЕМЕННЫХ ПАПКАХ И РЕЗЕРВНЫХ КОПИЯХ.**

- The user explicitly requested removal of duplicate builds on 2026-09-18. Old copies were unregistered and moved to recoverable Trash; do not restore them automatically.
- Build artifacts and backups retained after validation must be archives, not additional registered app bundles. A temporary candidate may exist during compilation and verification, but must not be launched as a second copy.
- The sole installed app now has bundle identifier `app.duotlet.Duotlet` and an Apple Development signature. The approved one-time legacy migration is complete; all subsequent installations must pass the normal continuity check.
