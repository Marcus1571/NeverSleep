# KB.md — canonical reference

Exhaustive reference. README is the pitch; anything factual about behavior, design, or history lives here. One source of truth per fact.

## Feature contract from NoSleep

Reproduced from NoSleep v1.5.x source and changelog (research trail in `findings.md` §2). NeverSleep v1.0 target = full parity on this table.

| # | Feature (NoSleep wording) | NeverSleep plan |
|---|---|---|
| 1 | Never sleep on AC Adapter | Independent toggle, applies only when the Mac is on AC |
| 2 | Never sleep on Battery | Independent toggle, applies only on battery |
| 3 | Menu-bar "Zz" toggle | Filled Zz = awake-when-closed active; outline = inactive (**implemented 0.2.1**, imitating the original's `ZzActive`/`ZzInactive` template-image swap on state change); one click toggles the mode that matches the *current* power source |
| 4 | Use black and white menu bar icons | Preference: monochrome vs. accent-colored icons |
| 5 | Use double click to activate | Double-click on the icon toggles like the single-click path |
| 6 | Require password on display opening | **Dropped** (decision, 2026-11-09): no auto-lock at all — closing the lid turns the display off natively and the session stays unlocked; users lock by hand (`Control-Command-Q`) when they want to |
| 7 | Start NoSleep utility on system startup | Login item (**implemented 0.2.0**): `SMAppService.mainApp`, macOS 13+ (LaunchAgent plist fallback on 11–12); menu checkmark + Preferences toggle |
| 8 | Automatically check for updates | Sparkle or osx-updater equivalent — decide at implementation |
| 9 | Command-line interface | `neversleepctl` (state on/off/status), so scripts can flip it like `NoSleepCtrl` could |
| 10 | State survives reboot | NoSleep persisted via NVRAM from the kext; NeverSleep persists in defaults and re-arms at launch — but *only while the app runs* (see "Never leaves the Mac awake", below) |

Explicitly out of contract (was never NoSleep behavior): forcing the display off while the lid is open, ignoring thermal limits, preventing idle sleep while the lid is open (that's Caffeine/Caffeinate territory).

## Mechanism history (how NoSleep worked, and why it stopped)

- NoSleep's kext hooked `IOPMrootDomain`, watched clamshell + power-source events, and flipped the root domain's sleep behavior so a closing lid did not trigger sleep. Its two power-source-mode settings and NVRAM persistence were kext responsibilities.
- Modern macOS blocks kernel-extension installs this way (SIP, user-approved kext loading). NoSleep, InsomniaX predate that and are unmaintained (~2019-2023 era).
- The userland private-key trick (`kIOPMAssertionAppliesOnLidClose` + `IOPMAssertionDeclareUserActivity`) was the interim successor, until 10.13 made the key entitlement-restricted; Fermata shells out to pmset instead. Details in `findings.md` §3.

## Approach (NeverSleep)

- **Mechanism:** toggle `pmset ... disablesleep` through a **privileged helper** (SMJobBless-style, or an authorized `SMAppService` flow). Never leaves the machine altered after the app exits.
- **Semantics that matter:**
  - Night-night verbs: `-b` targets the battery charger view, `-a` all charger views. The exact mix is an implementation decision; the *contract* is only that toggles power-source-scoped behavior like NoSleep's separate checkboxes did.
  - Sleep suppression applies on the current power source only when the matching NoSleep-style toggle is on — behavior at the moment the lid closes, not a permanent system setting.
  - Quit restores normal behavior (pmset value verified equal to pre-app baseline; baseline is stored when the app starts).
- **Display behavior:** no touching displays. On lid close macOS turns the display off on its own; NeverSleep only stops the *sleep*, hence the "exactly like an open lid, minus the screen" effect the operator asked for.
- **Never locks anything:** the operator explicitly rejected the NoSleep auto-lock option — a closed lid must only mean "display off" (native), with the session unlocked. Locking stays a manual action (`Control-Command-Q`).
- **Heat warning** (user-visible): closed lid = reduced cooling; surface this once in the README, never nag in-app.

## Build & test

- Toolchain: SwiftPM with the Command Line Tools only (no Xcode project). `swift build -c release`, then `Scripts/make-bundle.sh` assembles `build/NeverSleep.app` (Info.plist, icns, ad-hoc signature). Menu bar via `NSStatusItem` (not `MenuBarExtra`), SwiftUI only for the Preferences window. Three SwiftPM targets: `NeverSleepCore` (library — anything the app or CLI calls must be `public`), `NeverSleep` (app, entry in `main.swift`), `neversleepctl` (CLI).
- If `swift build` fails on *any* package with `Undefined symbols … PackageDescription.Package.__allocating_init`, the Command Line Tools have stale `*.private.swiftinterface` files in `ManifestAPI/PackageDescription.swiftmodule`; move them out or reinstall CLT (`findings.md` §8).
- Runtime log: `~/Library/Logs/NeverSleep.log` (plus os_log subsystem `app.legba.neversleep`).

### pmset output the parsers rely on (verified macOS 27, 2026-11-09)

- `pmset -g`: `SleepDisabled` line appears only when non-zero; absent = 0.
- `pmset -g batt`: first line `Now drawing from 'AC Power'` or `'Battery Power'` (quoted, no colon).
- `pmset` writes need root: each write goes through one `osascript … with administrator privileges` dialog; reads are unprivileged. Every write is verified by reading `pmset -g` back.
- No CI. Verification expectations: behavior claims come from a real Mac run (admin auth included); from elsewhere, only compile checks count.
- icon responsibilities: `art/neversleep-app-icon.svg` → `.icns` via `iconutil` on the Mac (SVG → PNG intermediate at 16/32/64/128/256/512/1024 px), `art/menubar-z*.svg` → in-app template-recolorable PDFs. Conversion happens Mac-side, not in this repo's CI (there is none).

## Naming-collision note

An unrelated store product "NEVER SLEEP - Even Lid Closed!" exists; no conflict identified (different publisher, platform, and codebase), but the name is not first-come-clean. Revisited only if it ever becomes a real trademark/search-visibility problem.

## References

- Original repo: <https://github.com/integralpro/nosleep> (GPL-2.0)
- Original distribution page: <https://nosleep.macupdate.com>
- Fermata (source of the pmset insight + the mechanism history): <https://github.com/iccir/Fermata>
- `disablesleep` examples: <https://github.com/Moarram/wake>, HN thread 2026 (link in `findings.md` §4)
- KeepingYouAwake (negative result for closed lid): <https://github.com/newmarcel/KeepingYouAwake>
