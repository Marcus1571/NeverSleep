# STATUS.md

Founded: 2026-11-09 (operator named the project "NeverSleep", successor to NoSleep).

## Current state

- Repo `Marcus1571/NeverSleep` created public 2026-11-09, checkout exists on the operator's machines per the two-checkout convention.
- Research complete — original NoSleep located (repo, MacUpdate page, changelog), full feature map extracted from its source, modern macOS mechanism identified. All evidence in `findings.md` with a verdict.
- Design decided (see `KB.md` "Approach"): SwiftUI menu-bar app + privileged helper toggling `pmset ... disablesleep`, restore-on-quit, separate battery/AC state.
- Icon: recolored derivative of the NoSleep "Zz" asset shipped under `art/` (colors changed at the operator's request; provenance comment in each file).

## In flight

**v0.1.1 released** (first tagged release) — v0.1 **compiles and is installed** on the operator's Mac (2026-11-09): `swift build -c release` clean, `Scripts/make-bundle.sh` produces an ad-hoc-signed arm64 `.app`, copied to `/Applications` and launched (log shows baseline captured, AC power detected). Compile fixes + three runtime bug fixes in `findings.md` entry 8. **Partly smoke-tested 2026-11-09 (log-verified):** toggle on → one admin prompt → `SleepDisabled=1` verified (`-b` scope accepted on Apple Silicon, macOS 27); quit → baseline restored to 0 with a single prompt. **Still to test:** actually closing the lid while suppressed. Known gap: the per-source preference toggles only drive the icon state on power-source change; they do not apply pmset by themselves yet.

**v0.2.0 released** (2026-11-10): launch-at-login via `SMAppService.mainApp` (dotbar's mechanism; parity feature 7), checkmark menu item + Preferences toggle, setting finally persists across restarts. Registered bundle is visible/reversible in System Settings › General › Login Items. Built and reinstalled to `/Applications` same day.

**v0.2.1 released** (2026-11-10): NoSleep-style menu-bar states (parity feature 3) — filled Zz while suppressing, outline Zz while normal sleep (outline glyph derived from the original's `Icons/ZzOutline.svg`, recolored per the art provenance rules; both shipped as vector PDFs, template in B/W mode).

**v0.3.0 released** (2026-11-10): privileged root helper (`neversleep-helper` LaunchDaemon, installed once via a single admin prompt) — toggles, quit-restore and `neversleepctl` are password-free from then on; per-write osascript prompts remain as fallback when declined. Daemon protocol + security model in `KB.md` "Privileged helper". **0.3.1 hotfix same day:** the install script's `bootout && bootstrap` chain skipped the bootstrap on first install (bootout exits non-zero when not loaded), so 0.3.0 installs never started the daemon — fixed, one reinstall prompt required for 0.3.0-era installs.

**v0.3.2 hotfix same day:** the daemon's verification looked for `"SleepDisabled 1"` (space) but `pmset -g` separates with tabs — writes of 1 took effect yet were reported `ERR verify`, so every activation showed "pmset rejected" while the Mac actually went quiet. Tolerant parser + `parsed=` field in the daemon log + protocol v2 (old daemons fail handshake → reinstall offered on next toggle).

**v0.3.3 hotfix same day:** inactive menu-bar icon clipped at the top right — the outline glyph's original canvas is wider (22.5×20) than the 20×20 box it was pasted into; now scaled uniformly to fit, both states share the same icon box.

**v0.4.0 released** (2026-11-10): full diskled-plus distribution pipeline — Developer ID–signed app (hardened runtime), notarized + stapled DMG, Sparkle 2.8 self-updating (startup + weekly, auto-install, Check for Updates… ⌘U), EdDSA-signed appcast on repo `main`. Reverses the 2026-11-09 "ad-hoc only / no auto-updates" decision (operator acquired the Developer ID; feature 8 back in contract). `make-bundle.sh` retired in favor of `make-app.sh`/`make-dmg.sh`/`make-appcast.sh` (version now follows the latest CHANGELOG heading automatically). Local `/Applications` install upgraded to the signed build same day. Note: the running root daemon is still the 0.3.x protocol-v1 build — the next toggle offers the one-time helper reinstall (protocol v2), after which all toggles are password-free. (This note is resolved: the reinstall happened — log shows `OK neversleep-helper/2` from 2026-11-10 19:02 on.)

**v0.4.1 released** (2026-11-11): unclean-death recovery. The operator's Mac rebooted while suppression was active; `SleepDisabled 1` survived the reboot, the app relaunched into its "already permanently suppressed" read-only gate, and a stack of five bugs left the menu dead ("Restore normal sleep" no effect, icon stuck filled, "Power source: Unknown") with no way back from the app — cleared manually via `neversleepctl restore`. Fix: an ownership marker distinguishes NeverSleep's own leftover (adopted at startup: toggle live, baseline forced to 0) from a genuinely external config (read-only, as designed for macai). Also: `menu.autoenablesItems = false` so `isEnabled=false` is actually honored (AppKit re-enabled targeted items before), toggle-off never blocked by a missing per-source preference, the 5 s poll runs in all modes and reflects the **live pmset state** (new quiet `SleepController.isSleepSuppressed()`), and the external-mode menu item is honestly labeled. Full detail in `CHANGELOG.md` 0.4.1 and `findings.md` §11.

**v0.4.2 released** (2026-11-11, hotfix same day): v0.4.1's ownership marker was a UserDefaults suite — which turned out **not to be shared** between the bundled app and the bare `neversleepctl` (a suite named like the app's own bundle id resolves differently in the two process kinds; the ctl's marker write was invisible to the app). Marker moved to a fixed file, `~/Library/Application Support/NeverSleep/owns-suppression`. E2E re-verified live: ctl suppress → relaunch adopts → graceful quit restores 0 and removes the marker; marker-less suppression still gates read-only. Detail in `CHANGELOG.md` 0.4.2 and `findings.md` §12.

## Not started (ordered)

1. SwiftUI `MenuBarExtra` skeleton: one toggle, filled/outline icon states, quit item.
2. Privileged helper: prompt once (SMJobBless-style), then `pmset -b disablesleep 1|0` on battery (the exact AC-side wording, `-a` vs per-source, is decided at implementation time; see `findings.md`).
3. Quit = restore: app delegates `applicationWillTerminate` + explicit toggle-off on sign-out to never leave the Mac awake after the app exits.
4. Battery/AC separate toggles + live power-source detection (read out of IOPS).
5. ~~auto-lock~~ dropped (operator decision — closed lid must never lock the session).
6. ~~Preferences polish (launch item, B/W vs colored icons)~~ — B/W icons shipped in v0.1; **launch item shipped in v0.2.0** (2026-11-10): `SMAppService.mainApp`, menu checkmark + Preferences toggle.
7. Preferences surface mirroring the NoSleep pane (startup item in place; remaining: parity check against the feature contract in `KB.md` before calling anything complete).
8. Packaging + signed release discipline before publicizing the repo anywhere.

## Open questions / blocked

- RESOLVED this session: the operator's other Mac ("macai", benold_ai) already runs deliberately with `SleepDisabled 1` set *permanently* (configured via a Claude Code session to stay awake with the lid closed forever — that box's intended mode). Reference config, not something NeverSleep manages. Consequence for v1: at startup, read `pmset -g`; if `SleepDisabled 1` is already present, warn "already permanently awake" and enable nothing, instead of double-managing an existing OS setting.
- Spotlight/behavior differences on Apple Silicon with `disablesleep` (classic PM path) — needs one laptop test before claiming parity; treat as unverified until then.

## Decisions this session

- App name: NeverSleep (operator's choice) — see `findings.md` for a naming-collision note (an entirely separate "NEVER SLEEP" watch app exists on the store; unconflicting).
- License: MIT for code, GPL-2.0 inherited only for the derived art (see `AGENTS.md`).
- Target mechanism: pmset-based, not a revival of the kext path (see `findings.md` verdict entries 1 and 4).


## In flight (2026-11-09, this session)

- **Full v0.1 codebase written**: SPM executable targets `NeverSleep` (app) + `neversleepctl` (CLI) + `NeverSleepCore` (log, shell runner, pmset parsing, `SleepController` with baseline capture/restore + write verification, power-source read via `pmset -g batt`, `AdminPrivileges` (osascript auth dialog v1),→ replaced by explicit drop, `SettingsStore` (separate AC/battery toggles, B/W icons, LaunchAgent login item). Status-bar UI via `NSStatusItem` + SF-Symbol "zzz" (template/colored per setting) — identical behavior on macOS 11 → 26+, Intel + Apple Silicon: **no version or arch branches by design**; the runtime *probes* (reads pmset state, tries `-b` scope first with `-a` fallback, verifies every write, refuses to touch a machine already in `SleepDisabled 1`).
- **Scripts**: `Scripts/make-bundle.sh` (Mac-side: swift build + assemble .app + Info.plist from art/ icon + ad-hoc codesign) and `Scripts/make-iconset.sh` (SVG→PNG→icns via qlmanage/rsvg-convert).
- **Compiled 2026-11-09** on the Mac — see "In flight" above.
- **Deliberately deferred** (features present in NoSleep, still absent here): double-click activation (stub), lid-close *detection* for lock-screen timing (v1 locks immediately on enabling suppression when the option is on; IOKit `AppleSmartBattery` "AppleClamshellState" read planned for v0.2), Sparkle auto-updates, IOKit-based power-source notifications (currently a 5 s poll).
