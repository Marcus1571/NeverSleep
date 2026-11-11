# findings.md — research log

Investigations with sources and verdicts, newest last. Nothing here is adopted design; adopted design lives in `KB.md`.

## 1. Original NoSleep — page, repo, provenance (2026-11-09)

- Repo: <https://github.com/integralpro/nosleep> (author Pavel Prokofiev). License **GPL-2.0**. Repo banner (and the MacUpdate listing) states it is **deprecated**: "no longer maintained, and same behavior could be achieved by using `pmset` or `caffeinate`" — kept "only as an example of simple kext implementation".
- MacUpdate page: <https://nosleep.macupdate.com> — free/donationware, ~1.7 MB, last listed update Apr 2019 (v1.5.1), supported through roughly macOS 10.12/10.13-era, >417k downloads. Last release on GitHub: `NoSleep-1.5.0.dmg` (v1.5.0, macOS 10.13 support). Changelog in `Utilities/ChangeLog.html` inside the repo confirms that timeline.
- Verdict: found both the distribution page and the source repo; it is the exact app ("NoSleep", Zz menu-bar icon, pref pane) the operator remembers.

## 2. NoSleep's full feature map from source (2026-11-09)

From `NoSleep/Common/GlobalConstants.h`, `NoSleep/NoSleepPref/en.lproj/NoSleepPref.xib` (the settings pane), `NoSleepHelper/*`, `Utilities/ChangeLog.html`, `Icons/*`:

- Two independent master toggles: "Never sleep on AC Adapter" and "Never sleep on Battery" (separate state per power source — `kNoSleepModeAC`, `kNoSleepModeBattery`; current state = whichever applies, `kNoSleepModeCurrent`).
- Menu-bar "Zz" icon toggle with two visages (outline = inactive, filled = active; `ZzOutline.svg` / `ZzFilled.svg`, and `IsBWIconEnabled` to use black-&-white menu-bar icons).
- Loop-mode extras recorded in the changelog/UI strings:
  - "Start NoSleep utility on system startup" (login item, plus kext loaded at boot).
  - "Automatically check for updates" (Sparkle).
  - "Require password on display opening" — auto-lock: with lid closed + sleep suppressed, force the lock screen (`SACLockScreenImmediate`, kext message `kNoSleepCommandLockScreenRequest`), i.e. the Mac stays awake but is secured when the lid is shut.
  - "Use double click to activate" (double-click the menu-bar icon toggles).
- Scriptability: `NoSleepCtrl` command-line tool for scripting the state.
- Persistence: kext writes the packed state to NVRAM ("IORegistryCurrentSleepMode") and re-applies it after reboots ("Reloading of the previous state after reboot", changelog 1.3.0).
- Mechanism (the part that died): a kext (`NoSleepExtension`) intercepts the clamshell (lid) events and power-source notifications on `IOPMrootDomain` and forces the root domain's `SleepDisabled` behavior off so a closing lid does not trigger sleep; user client exposes enable/disable + lock-screen commands (selectors 0/1/2).

Verdict: this is the contract NeverSleep must reproduce; recorded in `KB.md`.

## 3. Why the kext path is dead (2026-11-09)

- Fermata's README <https://github.com/iccir/Fermata>: InsomniaX/NoSleep-style kexts broke against **System Integrity Protection** and **User-Approved Kernel Extension Loading**.
- Also, on a macOS 10.13 update Apple moved the private key `kIOPMAssertionAppliesOnLidClose` behind the restricted `com.apple.private.iokit.assertonlidclose` entitlement, so Fermata's original userland trick (declare user activity + that key) stopped being available to unsigned apps; its fallback was to shell out to pmset.
- NoSleep itself stopped at 10.13-era support.

Verdict: do not build on the kext or on the userland/private-key path; both have the same ceiling.

## 4. The mechanism that works today: `pmset disablesleep` (2026-11-09)

- `pmset -b disablesleep 1` / `sudo pmset -a disablesleep 1` disables sleep while the lid is closed (works on battery and, with `-a`, system-wide; live example + caution in the `Moarram/wake` README and the 2026 Hacker News thread "Caffeine-like utility to keep you MacBook awake with its lid closed").
- Undocumented key (not in pmset's man pages), toggled instantly, reverts with `0`. Requires root, which implies a privileged helper or an equivalent authorized flow for a menu-bar app.
- Caveat that belongs in any user-facing docs: a closed-lid Mac has reduced cooling — overheating risk in a bag/enclosed space.
- KeepingYouAwake (caffeinate wrapper) deliberately does **not** prevent closed-lid sleep; `caffeinate` alone cannot. Caffeine same. This is the operator's expectation ("caffeine fails to do what I want") confirmed by those projects' own docs.

Verdict: `disablesleep` via a privileged helper is the adopted mechanism for NeverSleep (see `KB.md` "Approach"). Unverified on Apple Silicon laptops at the time of writing — one real test needed (tracked in `STATUS.md`).

## 5. Prior art to stay polite about (2026-11-09)

- Amphetamine (App Store, free) + the open-source Amphetamine Enhancer helper already covers closed-display sleep prevention with conditions. NeverSleep's differentiator is lean parity with NoSleep's exact contract (separate battery/AC toggles, double-click, auto-lock-on-close, CLI) rather than Amphetamine's session/rule sprawl.
- Fermata's approach (auto-detect an app preventing idle sleep and "upgrade" it to prevent *lid close* sleep too) is a clever optional nicety worth an entry on the idea list, not a core requirement.
- A different store product is already called "NEVER SLEEP - Even Lid Closed!" (`id1574505861`). Different platform context and license, but the name collision is noted; the operator's chosen name stands.

## 6. Art provenance (2026-11-09)

- The "Zz" glyphs were taken from the original repo's `Icons/` (`ZzFilled.svg`, color `#000000`) and recolored (`#4EC9E8` on `#10141F` rounded square for the app icon; same recolor, 35% opacity for the inactive menu-bar state). Same glyph geometry, different colors — per the operator's explicit request ("copy the icon … but change the colors so it's not such a blatant copy"). GPL-2.0 is inherited for these files; see `art/ART-LICENSE.md`.

## 7. macai audit — the "permanent" precedent confirmed (2026-11-09)

- The operator confirmed the context: **macai was deliberately configured (by a Claude Code session) to run perfectly with the lid closed and stay that way** — it's that box's intended modus operandi, applied as permanent settings, not an accident to be "fixed". SSH access was set up this session (key-based, alias `macai`) and `pmset` was read directly.
- Found, exactly matching that intent: system-wide **`SleepDisabled 1`** (the permanent `pmset disablesleep 1` state), **AC: `sleep 0`, `displaysleep 0`** (fully awake, display always on, lid never matters), **battery: `sleep 1`, `displaysleep 2`**. `pmset -g` live showed "sleep prevented by screensharingd" — the machine spends its life screen-shared.
- Verdict: the mechanism is proven in daily use on that box, and its state (a *permanent* system-wide knob) is precisely what NeverSleep replaces with a *runtime* toggle: same effect on demand, automatically reverted on quit — so the laptop's normal sleep behavior is intact 99% of the time, unlike macai's always-on configuration. NeverSleep must not touch machines already in `SleepDisabled 1`; detect and warn instead of double-managing.

## 8. First real compile on the operator's Mac (2026-11-09)

- **Toolchain trap:** `swift build` failed for *any* package (even an empty one) with `Undefined symbols … PackageDescription.Package.__allocating_init`. Cause: stale `*.private.swiftinterface` files (Feb 2024) left in the Command Line Tools' `ManifestAPI/PackageDescription.swiftmodule` by an older CLT install; the compiler prefers them over the current interface and links against an API the current `libPackageDescription.dylib` no longer exports. Fix: move those two files out (or reinstall CLT). Verdict: machine issue, not a project issue; `Package.swift` was fine.
- **pmset output facts observed on macOS 27:** `pmset -g` omits `SleepDisabled` entirely when it is 0; `pmset -g batt` reports the source as `Now drawing from 'AC Power'` (quoted, no colon). The v0.1 parsers assumed otherwise, which would have made the power source always "Unknown" (menu toggle could enable but never disable) and every disable fail verification. Both fixed in the parsers.

## 9. Deploy footgun: `cp -R` into an existing .app directory silently keeps the old bundle (2026-11-10)

While reinstalling v0.2.0 over the running v0.1.1 install, `cp -R build/NeverSleep.app /Applications/NeverSleep.app` did not replace the app — with an existing destination directory, `cp -R` copies the source **inside** it. Result: the relaunch ran the old v0.1.1 binary while `/Applications/NeverSleep.app/` contained a nested duplicate `NeverSleep.app`; everything "succeeded" and the version log line betrayed it (`launched: build=0.1.1` after a 0.2.0 build).

**Verdict:** replacing an installed .app is `rm -rf` + `ditto` (or `cp -RpN` semantics consciously chosen), and the log's `launched: build=` line plus `plutil -p .../Info.plist | grep ShortVersion` on the *installed* path is the cheap post-install verification every install should end with. `scripts/make-bundle.sh`'s "copy to /Applications" instruction remains correct only for a non-existing destination.

## 10. README screenshot capture recipe (2026-11-11)

How the `docs/img/` set was captured live (mirrors diskled-plus findings "README screenshot capture recipe"). The installed app must be running from /Applications; Screen Recording + Accessibility are needed for the terminal host.

- **Status-item geometry:** `osascript -e 'tell application "System Events" to tell process "NeverSleep" to get {position, size} of menu bar item 1 of menu bar 1'` → e.g. `1646, 3, 20, 24`. `menu bar 1` is correct on this macOS build (an earlier session's `menu bar 2` query was the wrong index, not a permissions failure).
- **Icon states:** crop the item region with `screencapture -x -R1646,0,20,26 <file>` (2× retina). Filled shot needs suppression ON, outline needs it OFF — toggling through the real menu keeps the shots honest.
- **Opening the menu:** an AX `click menu bar item 1` only highlights the item and does NOT open the menu on this build. Post a real mouse click with a CGEvent helper (`swift /tmp/click.swift <x> <y>` — CGEvent mouseDown+mouseUp at the item, needs Accessibility); the menu opens and `menu 1 of menu bar item 1` becomes queryable. Menu items are then clickable via AX (`click menu item "Preferences…" of menu 1 of ...`).
- **Menu shot:** `screencapture -x -R1640,29,245,180` while the menu is open.
- **Preferences window:** AX-click the "Preferences…" menu item, then `tell application "NeverSleep" to activate` — the window opens BEHIND the frontmost app otherwise (a first capture attempt grabbed unrelated window content and was deleted unused). Crop to the queried window position/size, close via the AXCloseButton.
- **Menu-bar redraw lag (watch out):** right after a state toggle, the menu bar can still display the PREVIOUS icon state for several seconds on this macOS build — the app sets the image immediately (log + AX state confirm), the bar just redraws lazily. An "impossible" capture (outline while suppressed) was this lag, not a bug: re-capture after a pause, or verify against `pmset -g` + the app log before suspecting the renderer.

## 11. The v0.4.1 incident: an unclean death wedged the app into a dead read-only mode (2026-11-11)

**Reported by the operator:** "Restore normal sleep" has no effect and the icon is stuck on the filled state; menu showed "Power source: Unknown".

**Root cause chain (all verified against `~/Library/Logs/NeverSleep.log` and live `pmset`):**
1. Suppression was toggled on at 00:14; the Mac rebooted at ~09:00 (verified `last reboot`: shutdown 09:00, boot 09:54) — the app never got its quit-restore, and `SleepDisabled 1` **survived the reboot** (pmset writes are durable — treat that as a standing fact).
2. On relaunch the startup gate found `SleepDisabled=1`, captured it as baseline (1), and locked the app read-only ("machine already permanently suppressed") — misclassifying NeverSleep's **own leftover** as a deliberate external config (the macai case). Quit-restore then no-oped (`already at baseline SleepDisabled=1`), so the state could never clear itself.
3. The read-only path `return`ed before power polling → "Power source: Unknown" forever.
4. `item.isEnabled = false` is **not honored** by AppKit when `NSMenu.autoenablesItems` is its default `true` and the target has no `validateMenuItem` — the "disabled" toggle was clickable (log proves the clicks fired).
5. In read-only mode the click sent the wrong direction: title used effective state (`active || externallySuppressed`) but the action sent `!active` → toggle **on** → "Already suppressed".
6. Even had the direction been right, `handleToggle`'s guard (`targetFor(source) != nil || on`) blocked toggling **off** when the power source was Unknown (no preference can exist for it).

**Fix (v0.4.1):** ownership marker (shared defaults suite `app.legba.neversleep`, key `ownsActiveSuppression`; set on verified enable, cleared on verified disable — kept correct from `neversleepctl` too since both go through `SleepController`); startup adopts marked leftovers (baseline 0, toggle live) and keeps the read-only gate only for marker-less external state; `autoenablesItems = false`; off-toggle never guarded; poll runs everywhere and reflects live state via a quiet `isSleepSuppressed()` read.

**Verdict / standing facts:** (a) `disablesleep` persists across reboots — every future session must expect leftovers after crashes/forced shutdowns, and the marker is what makes them recoverable; (b) `NSMenu.autoenablesItems` silently overrides per-item `isEnabled` — any future "disabled menu item" in this project needs the auto-enable off or a `validateMenuItem`; (c) E2E-verified live on this Mac: adopt path (marker + 1 → adopted, poll shows `power=AC Power suppressed=true`), external path (1 without marker → read-only, now with working power read), and restore via `neversleepctl restore` (password-free through the protocol-v2 helper).
