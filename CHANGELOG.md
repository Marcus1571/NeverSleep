# CHANGELOG

All notable changes. Format: Keep a Changelog-ish, versioned per the release sequence in `USER.md`.

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
