# CHANGELOG

All notable changes. Format: Keep a Changelog-ish, versioned per the release sequence in `USER.md`.

## [Unreleased] — 2026-11-09: first real compile + install on the Mac (commit 1a17886)

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
