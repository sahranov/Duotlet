# Mandatory installation rule

**НИКОГДА НЕ ПЕРЕЗАПИСЫВАЙ УСТАНОВЛЕННЫЙ DUOTLET СБОРКОЙ С AD-HOC ПОДПИСЬЮ. ЭТО ЛОМАЕТ ВЫДАННЫЕ macOS РАЗРЕШЕНИЯ ПРИ КАЖДОЙ ПЕРЕСБОРКЕ.**

**НЕ ПРЕДЛАГАЙ УДАЛЯТЬ И ЗАНОВО ДОБАВЛЯТЬ РАЗРЕШЕНИЕ НА ЗАПИСЬ ЭКРАНА КАК ОБЫЧНЫЙ ШАГ ОБНОВЛЕНИЯ. НЕ СБРАСЫВАЙ TCC И НЕ МЕНЯЙ РАЗРЕШЕНИЯ, ЧТОБЫ КОМПЕНСИРОВАТЬ НЕПРАВИЛЬНУЮ ПОДПИСЬ.**

**ОБЕЩАНИЕ «БОЛЬШЕ ТАК НЕ ДЕЛАТЬ» НЕ ЗАМЕНЯЕТ ТЕХНИЧЕСКУЮ ПРОВЕРКУ. НЕ ОБХОДИ ЗАЩИТУ УСТАНОВКИ ПРЯМЫМ КОПИРОВАНИЕМ, ПЕРЕИМЕНОВАНИЕМ, ПЕРЕПОДПИСЫВАНИЕМ ИЛИ ОСЛАБЛЕНИЕМ CODE REQUIREMENTS.**

- Default `./build.sh` only packages `output/Duotlet.app`. Do not launch the ad-hoc artifact under the installed app's identity.
- Installation requires a real Apple signing identity and a successful `scripts/verify-install-identity.py` check against the existing installation. Keep bundle identifier and signing team consistent across updates.
- Before replacing an installed build, verify the new build satisfies the old build's designated requirement. Successful compilation or ordinary signature verification alone is insufficient.
- If the required signing identity is unavailable or continuity fails, finish compilation/tests in the workspace and report the signing blocker. Leave the installed app and its permissions untouched.
- Moving from a historical ad-hoc identity to a proper release identity is a separate, explicitly planned one-time migration; never silently perform it during a UI fix or ordinary update.
- Do not claim the installed app or screen-capture effect is fixed merely because the staged build or regression tests pass. State what remains unverified.

This rule records repeated permission breakage during local installs, reported by the user on 2026-09-18. Preserve it across future tasks and summaries.
