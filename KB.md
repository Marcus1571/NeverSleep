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
| 8 | Automatically check for updates | **Implemented 0.4.0**: Sparkle 2.8 embedded — startup + weekly checks, automatic installs, Check for Updates… menu item (⌘U); appcast EdDSA-signed on repo `main` (Dropped 2026-11-09 for lack of a Developer ID; reversed 2026-11-10 when the operator acquired one — see the 0.4.0 CHANGELOG entry) |
| 9 | Command-line interface | `neversleepctl` (state on/off/status), so scripts can flip it like `NoSleepCtrl` could |
| 10 | State survives reboot | NoSleep persisted via NVRAM from the kext; NeverSleep persists in defaults and re-arms at launch — but *only while the app runs* (see "Never leaves the Mac awake", below) |

Explicitly out of contract (was never NoSleep behavior): forcing the display off while the lid is open, ignoring thermal limits, preventing idle sleep while the lid is open (that's Caffeine/Caffeinate territory).

## Mechanism history (how NoSleep worked, and why it stopped)

- NoSleep's kext hooked `IOPMrootDomain`, watched clamshell + power-source events, and flipped the root domain's sleep behavior so a closing lid did not trigger sleep. Its two power-source-mode settings and NVRAM persistence were kext responsibilities.
- Modern macOS blocks kernel-extension installs this way (SIP, user-approved kext loading). NoSleep, InsomniaX predate that and are unmaintained (~2019-2023 era).
- The userland private-key trick (`kIOPMAssertionAppliesOnLidClose` + `IOPMAssertionDeclareUserActivity`) was the interim successor, until 10.13 made the key entitlement-restricted; Fermata shells out to pmset instead. Details in `findings.md` §3.

## Approach (NeverSleep)

- **Mechanism:** toggle `pmset ... disablesleep` through a **privileged helper** — since v0.3.0, a root LaunchDaemon installed once by the app (see "Privileged helper" below; the ad-hoc-signed build deliberately skips the fussy SMJobBless/SMAppService.daemon registration APIs). Never leaves the machine altered after the app exits.
- **Semantics that matter:**
  - Night-night verbs: `-b` targets the battery charger view, `-a` all charger views. The exact mix is an implementation decision; the *contract* is only that toggles power-source-scoped behavior like NoSleep's separate checkboxes did.
  - Sleep suppression applies on the current power source only when the matching NoSleep-style toggle is on — behavior at the moment the lid closes, not a permanent system setting.
  - Quit restores normal behavior (pmset value verified equal to pre-app baseline; baseline is stored when the app starts).
- **Display behavior:** no touching displays. On lid close macOS turns the display off on its own; NeverSleep only stops the *sleep*, hence the "exactly like an open lid, minus the screen" effect the operator asked for.
- **Never locks anything:** the operator explicitly rejected the NoSleep auto-lock option — a closed lid must only mean "display off" (native), with the session unlocked. Locking stays a manual action (`Control-Command-Q`).
- **Heat warning** (user-visible): closed lid = reduced cooling; surface this once in the README, never nag in-app.

## Build & test

- Toolchain: SwiftPM with the Command Line Tools only (no Xcode project). Three SwiftPM targets: `NeverSleepCore` (library — anything the app or CLI calls must be `public`), `NeverSleep` (app, entry in `main.swift`, Sparkle-updated), `neversleepctl` (CLI), plus `neversleep-helper` (root LaunchDaemon target). Menu bar via `NSStatusItem` (not `MenuBarExtra`), SwiftUI only for the Preferences window.
- **Local dev build:** `swift build -c release`, then `scripts/make-app.sh` (ad-hoc by default). The version comes from the latest CHANGELOG heading; CFBundleVersion is the numeric stamp Sparkle compares.
- **Distribution build (Developer ID, notarized DMG, what GitHub Releases ship):** `scripts/make-dmg.sh <version> "Developer ID"` → signs the app + helper with the Developer ID Application cert (hardened runtime, timestamped), builds the DMG, notarizes via the shared `diskledplus-notary` keychain profile (same Apple ID as diskled-plus; override with `NOTARY_PROFILE=<name>`) and staples it. Output: `.build/dist/NeverSleep-<version>.dmg`.
- **Appcast:** after the DMG exists and the GitHub Release with that DMG asset is published, run `scripts/make-appcast.sh <version>` and push `appcast.xml` (push order: tag → GitHub Release with DMG → appcast commit → `git push origin main`; the feed's enclosure URL points at the release asset).
- **Install an update locally:** quit the running app, then `rm -rf /Applications/NeverSleep.app && ditto .build/app/NeverSleep.app /Applications/NeverSleep.app` (`cp -R` copies INTO an existing directory — findings.md §9) and relaunch.
- If `swift build` fails on *any* package with `Undefined symbols … PackageDescription.Package.__allocating_init`, the Command Line Tools have stale `*.private.swiftinterface` files in `ManifestAPI/PackageDescription.swiftmodule`; move them out or reinstall CLT (`findings.md` §8).
- Runtime log: `~/Library/Logs/NeverSleep.log` (plus os_log subsystem `app.legba.neversleep`).
- Sparkle notes: the appcast feed URL and `SUPublicEDKey` are baked into Info.plist by `make-app.sh`; the EdDSA private key lives in the login keychain (shared with diskled-plus — same operator key pair). Sparkle only runs when the app is a bundle; scheduled checks are startup + weekly with automatic installs.

### pmset output the parsers rely on (verified macOS 27, 2026-11-09)

- `pmset -g`: `SleepDisabled` line appears only when non-zero; absent = 0.
- `pmset -g batt`: first line `Now drawing from 'AC Power'` or `'Battery Power'` (quoted, no colon).
- `pmset` writes need root: each write goes through one `osascript … with administrator privileges` dialog; reads are unprivileged. Every write is verified by reading `pmset -g` back.
- No CI. Verification expectations: behavior claims come from a real Mac run (admin auth included); from elsewhere, only compile checks count.
- icon responsibilities: `art/neversleep-app-icon.svg` → `.icns` via `iconutil` on the Mac (SVG → PNG intermediate at 16/32/64/128/256/512/1024 px), `art/menubar-z*.svg` → in-app template-recolorable PDFs. Conversion happens Mac-side, not in this repo's CI (there is none).

## Privileged helper (v0.3.0+)

One admin password, ever. The first privileged write (first toggle, when no helper is installed) offers the install; accepting runs one osascript prompt that copies the helper out of the app bundle and bootstraps a LaunchDaemon. After that, **every** privileged operation — toggles, quit-restore, `neversleepctl` — is prompt-free.

- **Binary:** `Sources/neversleep-helper` (SPM target), shipped in the bundle as `Contents/Resources/neversleep-helper`, installed to `/Library/PrivilegedHelperTools/app.legba.neversleep.helper` (`root:wheel` 0755 — root must never execute anything user-writable, hence the copy out of the app bundle).
- **LaunchDaemon:** `/Library/LaunchDaemons/app.legba.neversleep.helper.plist` (`root:wheel` 0644), `RunAtLoad` + `KeepAlive`, program args `--socket /var/run/app.legba.neversleep.helper.sock --allow-uid <installing uid>`.
- **IPC:** line protocol over the local unix socket, one request per connection: `PING` → `OK neversleep-helper/<version>`; `SET <scope> <value>` (scope `-b`/`-a`, value `0`/`1` — anything else is `ERR protocol`) → `OK` / `ERR exit=<n>` / `ERR verify`. The daemon runs `/usr/bin/pmset` with that fixed argv (no shell), verifies by reading `pmset -g` back (same ground truth as the app), and answers `OK` only on verified writes.
- **Access model:** socket is 0666, but the daemon checks the peer UID (`getpeereid`) against `--allow-uid` and denies everyone else (denials logged). Any local process running as the installing user can ask the helper to flip sleep suppression — that is the power the installing user already has via one password prompt; nothing beyond it is exposed.
- **Failure handling:** daemon absent/wedged → client socket timeouts (3 s); the app attempts one reinstall mid-session, else falls back to the v1 per-write osascript prompts. Protocol version mismatch = treated as not installed (reinstall path). Helper log: `/Library/Logs/NeverSleepHelper.log` (1 MB rolling cap).
- **Manual uninstall:**
  ```sh
  sudo launchctl bootout system/app.legba.neversleep.helper
  sudo rm -f /Library/LaunchDaemons/app.legba.neversleep.helper.plist \
             /Library/PrivilegedHelperTools/app.legba.neversleep.helper \
             /var/run/app.legba.neversleep.helper.sock
  ```
  Reinstall happens automatically on the next toggle (one prompt).

## Naming-collision note

An unrelated store product "NEVER SLEEP - Even Lid Closed!" exists; no conflict identified (different publisher, platform, and codebase), but the name is not first-come-clean. Revisited only if it ever becomes a real trademark/search-visibility problem.

## References

- Original repo: <https://github.com/integralpro/nosleep> (GPL-2.0)
- Original distribution page: <https://nosleep.macupdate.com>
- Fermata (source of the pmset insight + the mechanism history): <https://github.com/iccir/Fermata>
- `disablesleep` examples: <https://github.com/Moarram/wake>, HN thread 2026 (link in `findings.md` §4)
- KeepingYouAwake (negative result for closed lid): <https://github.com/newmarcel/KeepingYouAwake>
