# STATUS.md

Founded: 2026-11-09 (operator named the project "NeverSleep", successor to NoSleep).

## Current state

- Repo `Marcus1571/NeverSleep` created public 2026-11-09, checkout exists on the operator's machines per the two-checkout convention.
- Research complete — original NoSleep located (repo, MacUpdate page, changelog), full feature map extracted from its source, modern macOS mechanism identified. All evidence in `findings.md` with a verdict.
- Design decided (see `KB.md` "Approach"): SwiftUI menu-bar app + privileged helper toggling `pmset ... disablesleep`, restore-on-quit, separate battery/AC state, optional auto-lock.
- Icon: recolored derivative of the NoSleep "Zz" asset shipped under `art/` (colors changed at the operator's request; provenance comment in each file).

## In flight

v0.1 codebase written (see "In flight (2026-11-09, this session)" below). — no, corrected: [2026-11-09] code exists, uncompiled.

## Not started (ordered)

1. SwiftUI `MenuBarExtra` skeleton: one toggle, filled/outline icon states, quit item.
2. Privileged helper: prompt once (SMJobBless-style), then `pmset -b disablesleep 1|0` on battery (the exact AC-side wording, `-a` vs per-source, is decided at implementation time; see `findings.md`).
3. Quit = restore: app delegates `applicationWillTerminate` + explicit toggle-off on sign-out to never leave the Mac awake after the app exits.
4. Battery/AC separate toggles + live power-source detection (read out of IOPS).
5. "Require password on display opening" option when lid closes.
6. Auto lock screen option and persistence add-ons.
7. Preferences surface mirroring the NoSleep pane (startup item, etc.), parity check against the feature contract in `KB.md` before calling anything complete.
8. Packaging + signed release discipline before publicizing the repo anywhere.

## Open questions / blocked

- RESOLVED this session: the operator's other Mac ("macai", benold_ai) already runs deliberately with `SleepDisabled 1` set *permanently* (configured via a Claude Code session to stay awake with the lid closed forever — that box's intended mode). Reference config, not something NeverSleep manages. Consequence for v1: at startup, read `pmset -g`; if `SleepDisabled 1` is already present, warn "already permanently awake" and enable nothing, instead of double-managing an existing OS setting.
- Spotlight/behavior differences on Apple Silicon with `disablesleep` (classic PM path) — needs one laptop test before claiming parity; treat as unverified until then.

## Decisions this session

- App name: NeverSleep (operator's choice) — see `findings.md` for a naming-collision note (an entirely separate "NEVER SLEEP" watch app exists on the store; unconflicting).
- License: MIT for code, GPL-2.0 inherited only for the derived art (see `AGENTS.md`).
- Target mechanism: pmset-based, not a revival of the kext path (see `findings.md` verdict entries 1 and 4).


## In flight (2026-11-09, this session)

- **Full v0.1 codebase written**: SPM executable targets `NeverSleep` (app) + `neversleepctl` (CLI) + `NeverSleepCore` (log, shell runner, pmset parsing, `SleepController` with baseline capture/restore + write verification, power-source read via `pmset -g batt`, `AdminPrivileges` (osascript auth dialog v1), LockScreen via `SACLockScreenImmediate`, `SettingsStore` (separate AC/battery toggles, lock-on-lid-close, B/W icons, LaunchAgent login item). Status-bar UI via `NSStatusItem` + SF-Symbol "zzz" (template/colored per setting) — identical behavior on macOS 11 → 26+, Intel + Apple Silicon: **no version or arch branches by design**; the runtime *probes* (reads pmset state, tries `-b` scope first with `-a` fallback, verifies every write, refuses to touch a machine already in `SleepDisabled 1`).
- **Scripts**: `Scripts/make-bundle.sh` (Mac-side: swift build + assemble .app + Info.plist from art/ icon + ad-hoc codesign) and `Scripts/make-iconset.sh` (SVG→PNG→icns via qlmanage/rsvg-convert).
- **Not compiled yet** — no macOS toolchain on LT. First action on the Mac: `swift build -c release` in the checkout, fix whatever the compiler flags, then `Scripts/make-bundle.sh`.
- **Deliberately deferred** (features present in NoSleep, still absent here): double-click activation (stub), lid-close *detection* for lock-screen timing (v1 locks immediately on enabling suppression when the option is on; IOKit `AppleSmartBattery` "AppleClamshellState" read planned for v0.2), Sparkle auto-updates, IOKit-based power-source notifications (currently a 5 s poll).
