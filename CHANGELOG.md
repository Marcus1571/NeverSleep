# CHANGELOG

All notable changes. Format: Keep a Changelog-ish, versioned per the release sequence in `USER.md`.

## [0.3.2] — 2026-11-10: fix the daemon's read-back verification (tab vs space)

Version bump: patch (fix of 0.3.0–0.3.1 daemon behavior). Bundle version (`Scripts/make-bundle.sh` Info.plist) 0.3.1 → 0.3.2.

**Bug fix (behavior change: writes of `1` verify correctly now)**
- `Sources/neversleep-helper/main.swift` — the daemon verified writes by looking for the literal `"SleepDisabled 1"` in `pmset -g` output, but real output separates label and value with **tabs** (`SleepDisabled\t\t1`, confirmed macOS 27). Every write of `1` therefore exited 0, actually took effect, yet was answered `ERR verify` — the app showed "pmset rejected disablesleep=1 in all scopes" while the machine *was* suppressed (a lie in the dangerous direction). Writes of `0` passed for the inverse wrong reason. The daemon now parses the value tolerantly (case-insensitive label, whitespace/`=` skipped, absent = 0) and logs the parsed value with every request. Before: user-visible failure on every activation, with real state diverging from what the app believed.
- `Sources/NeverSleepCore/PrivilegedHelper.swift` — protocol version 1 → 2: a running v1 daemon (every 0.3.0/0.3.1 install) now fails the handshake, so the next toggle offers the reinstall instead of silently talking to the broken verifier.

## [0.3.1] — 2026-11-10: fix helper install losing the launchd bootstrap

Version bump: patch (fix of 0.3.0's install path, no behavior beyond that). Bundle version (`Scripts/make-bundle.sh` Info.plist) 0.3.0 → 0.3.1.

**Bug fix (behavior change: the helper actually installs now)**
- `Sources/NeverSleepCore/PrivilegedHelper.swift` — the install root script chained `launchctl bootout … && launchctl bootstrap …`. On a first install the service is not loaded, so `bootout` exits non-zero and `&&` silently skipped the `bootstrap`: files landed, daemon never started, install() reported failure and every toggle kept using the v0.1 per-write osascript password (the exact opposite of the feature). Now the two launchctl steps run unconditionally after the file steps (`;`-joined, only the file steps chain with `&&`). Before: one password spent, zero prompts saved.

## [0.3.0] — 2026-11-10: privileged helper — one password ever (parity with NoSleep's KextHelper)

Version bump: minor (real new capability; pre-1.0, same scale per `USER.md`). Bundle version (`Scripts/make-bundle.sh` Info.plist) 0.2.1 → 0.3.0.

**Behavior change (new feature)**
- `Sources/neversleep-helper/main.swift` (new SPM target) — root LaunchDaemon performing the one privileged job: `pmset [-b|-a] disablesleep 0|1` on request over a local unix socket. Fixed argv (no shell), read-back verification before answering `OK`, `getpeereid` peer-UID check against the installing user, every request logged to `/Library/Logs/NeverSleepHelper.log`.
- `Sources/NeverSleepCore/PrivilegedHelper.swift` (new) — socket client (3 s timeouts on every op) + one-time install: copies the bundled helper to `/Library/PrivilegedHelperTools/app.legba.neversleep.helper` (root-owned, deliberately outside the user-writable app bundle), writes `/Library/LaunchDaemons/app.legba.neversleep.helper.plist`, bootstraps it, waits for handshake.
- `Sources/NeverSleepCore/SleepController.swift` — `AdminPrivileges` is now helper-first: first privileged write without a helper triggers the install offer once per session; declining (or a failed install) falls back to the v1 osascript-per-write path. `writeDisablesleep` routes both scopes through the new `pmset(scope:value:)` result. Before: one admin password per write — toggle on, toggle off, and every quit-restore each prompted.
- `Sources/NeverSleep/AppDelegate.swift` — the install offer alert ("last password you will ever type for NeverSleep"), plus a launch-time log line of helper presence.
- `Scripts/make-bundle.sh` — ships the helper binary in the bundle's Resources.
- Consequence for `neversleepctl`: script toggles are now password-free too once the helper is installed (parity feature 9's intent).

## [0.2.1] — 2026-11-10: NoSleep-style status icon states (parity feature 3)

Version bump: patch (visual refinement of the existing icon-swap behavior, per `USER.md`). Bundle version (`Scripts/make-bundle.sh` Info.plist) 0.2.0 → 0.2.1.

**Behavior change (visual)**
- `art/menubar-z-inactive.svg` — replaced: the inactive menu-bar glyph is now the **outline** Zz (geometry verbatim from the original repo's `Icons/ZzOutline.svg`, recolored to the NeverSleep cyan per the established art provenance rules; GPL-2.0 inherited). Before: the inactive state re-used the filled glyph at 35% opacity — barely visible in B/W template mode, and not the NoSleep look.
- `Sources/NeverSleep/StatusBarController.swift` — the status icon now swaps between the two **derived glyph PDFs** bundled by `make-bundle.sh`, imitating the original app's state swap (`ZzActive.pdf`/`ZzInactive.pdf`, both `template`): filled Zz while suppression is active, outline Zz while normal sleep. B/W mode renders both as template images (adaptive light/dark); colored mode keeps the existing tints (cyan = active, lightGray = inactive). Falls back to the SF-Symbol "zzz" when running without a bundle (bare `swift run`). Before: a single SF Symbol whose tint mocked the distinction — no filled/outline difference at all.
- `Scripts/make-bundle.sh` — now converts both `art/menubar-z-{active,inactive}.svg` to vector PDFs into the bundle's Resources (the pipeline KB already prescribed, previously never actually wired).

## [0.2.0] — 2026-11-10: launch at login (parity feature 7)

Version bump: minor (real new feature; pre-1.0, same scale per `USER.md`). Bundle version (`Scripts/make-bundle.sh` Info.plist) 0.1.1 → 0.2.0.

**Behavior change (new feature)**
- `Sources/NeverSleepCore/SettingsStore.swift` — `LoginItem` migrated from a bare `~/Library/LaunchAgents/` plist to `SMAppService.mainApp` (macOS 13+), dotbar's mechanism: the registered bundle shows up under System Settings › General › Login Items and is reversible there; this service status — not the stored default — is the live source of truth. The LaunchAgent plist path stays only as the fallback for macOS 11–12, where ServiceManagement's modern API does not exist. Errors from register/unregister are logged and an alert is shown from the menu path. Before: off-parity stopgap, invisible in System Settings.
- `SettingsStore.launchAtLogin` now also writes itself back to UserDefaults (before: the toggle was transient — it vanished on restart) and adopts the live service status at launch when the two have drifted (e.g. the login item was disabled in System Settings). No auto-registration at launch: changing off→on requires an explicit user action.
- `Sources/NeverSleep/StatusBarController.swift` — menu gains a "Launch at login" checkmark item (NoSleep-parity #7, done dotbar-style: state is read fresh from the service on every rebuild). Before: the only way to set it was nothing — the setting existed in code but had no UI.
- `Sources/NeverSleep/PreferencesView.swift` — Preferences gains a matching "Launch NeverSleep at login" toggle, wired through the same `SettingsStore.launchAtLogin` didSet.

## [0.1.1] — 2026-11-09: first real compile + install on the Mac

Version bump: patch (pre-1.0, so important fixes go one level down per `USER.md`). 0.1.0 was never tagged; it never compiled. Bundle version (`Scripts/make-bundle.sh` Info.plist) 0.1.0 → 0.1.1.

Code was written on LT without a toolchain; this is everything changed to make it compile and behave correctly against real macOS 27 output. Evidence in `findings.md` §8.

**Compile fixes (no behavior change)**
- `Sources/NeverSleepCore/*.swift`: types and members used by the app and CLI (`Log`, `SleepController` + `Outcome`/`Baseline`, `AdminPrivileges.shared`, `PowerState.sleepDisabled`, `PowerSource`, `PowerSourceReader.current()`, `SettingsStore`, `Outcome.isFailure`) marked `public` — they live in a separate SwiftPM module, so `internal` was invisible to `NeverSleep` and `neversleepctl`.
- `Sources/NeverSleep/NeverSleepApp.swift` → renamed `main.swift`: Swift only allows top-level code in `main.swift`. Entry now ends in `app.run()` instead of `NSApplicationMain(...)` (delegate is set by hand, no nib).
- `Log.swift`: `FileHandle.write(data:)` does not exist → `write(contentsOf:)`.
- `AppDelegate.swift`: `NSAlert(messageText:informativeText:)` does not exist → `NSAlert()` + set properties.

**Bug fixes (behavior change)**
- `PowerSourceMonitor.swift` — `PowerSourceReader.current()` looked for `AC Power:`; real `pmset -g batt` prints `Now drawing from 'AC Power'`. Now matches the quoted name. Before: source was always Unknown, so the menu toggle could enable suppression but never disable it.
- `PowerState.swift` — `sleepDisabled` returns 0 when `pmset -g` omits the `SleepDisabled` key (it does when the value is 0). Before: every disable failed post-write verification and the baseline was recorded as unknown.
- `SleepController.swift` — `restoreBaseline()` reads state first and does nothing if already at baseline. Before: every quit wrote pmset and showed the admin password dialog twice (quit item + `applicationWillTerminate`).
- `StatusBarController.swift` — menu is built in `init`. Before: on a machine already in `SleepDisabled 1` (read-only path) `update()` never ran and the menu was empty, with no Quit item.

## [0.1.0] — 2026-11-09

- Project founded; public repo created (`Marcus1571/NeverSleep`).
- Research complete: original NoSleep located (repo + MacUpdate page), full feature map extracted from its source, mechanisms for modern macOS identified; findings in `findings.md`, adopted design in `KB.md`.
- Recolored "Zz" icon derivative shipped under `art/` (app icon + two menu-bar states, recolored per the operator's request; GPL-2.0 inherited, `art/ART-LICENSE.md`).
- Governance layer installed (`README`, `AGENTS`, `STATUS`, `findings`, `KB`, this file) per the operator's two-backup git flow.
- No app code yet — see `STATUS.md` for the ordered plan.

- **v0.1.0 code baseline written** (uncommitted state → now committed): SPM Package.swift, `NeverSleep`/`NeverSleepCore`/`neversleepctl` sources, `Scripts/make-bundle.sh` + `Scripts/make-iconset.sh`.
- Design rule: one code path, macOS 11.0 floor, `NSStatusItem` UI (not `MenuBarExtra`), runtime probing of `pmset` capabilities with `-b`/`-a` fallback and post-write verification; never touches an already-`SleepDisabled 1` machine.
- Operator decisions 2026-11-09: auto-lock and auto-updates dropped entirely; no signed distribution (source-built, ad-hoc only); README gains precise compiling-agent instructions (SPM one-shot universal or arch-split + `lipo`, smoke test checklist, explicit "do not" list).
- Removed `Sources/NeverSleepCore/LockScreen.swift` and the lock-screen option everywhere (settings, UI, app logic).
