# NeverSleep

*Successor to [NoSleep](https://github.com/integralpro/nosleep) — close the lid, keep working.*

NeverSleep is a lean macOS menu-bar app that keeps a MacBook **fully awake with the lid closed**. Close the lid and keep talking on Teams / Zoom, keep a download running, keep a render going — the machine behaves exactly as if the lid were open, minus the display being on (the display turns itself off on its own; NeverSleep does not force it).

NoSleep solved this with a kernel extension, which modern macOS (SIP + user-approved kext loading) made unmaintainable; it was deprecated in ~2019. NeverSleep ships the same user-facing feature contract on the modern mechanism instead: a runtime toggle of the OS's own sleep-disable behavior ([KB.md — Approach](KB.md#approach)), applied only while NeverSleep runs and restored when it quits.

**What it does (v0 spec, representative — full contract in [KB.md — Feature contract](KB.md#feature-contract-from-nosleep)):**

- One menu-bar toggle (`Zz` icon, filled = awake): closes-the-lid sleep prevention, per power source
- Separate behavior on battery vs. AC, like NoSleep's two independent toggles
- State restored to normal macOS sleep behavior the moment the app quits

Read [STATUS.md](STATUS.md) for where development stands, and [findings.md](findings.md) for the research trail that led to the approach. The art works: it is a recolored derivative ([art/ART-LICENSE.md](art/ART-LICENSE.md)) — same "Zz" glyph as NoSleep, different color scheme so it is not a wholesale visual copy.

⚠️ A Mac awake with a closed lid has reduced cooling. NeverSleep is for use *while you are using the machine*, not for closed-lid tasks in a backpack all day.

## Compiling agent instructions (precise)

Run these on a Mac with Swift installed. Nothing else: no Xcode IDE session, no tool additions.

```bash
# 1. Prereq (once): command-line Swift. macOS 11+ host is enough.
xcode-select --install          # skip if swift already responds to: swift --version

# 2. Get the sources
git clone https://github.com/Marcus1571/NeverSleep.git ~/src/NeverSleep
cd ~/src/NeverSleep

# 3. Fix first, ask never: run the build; every compiler flag/error is the to-do list.
#    Never weaken a runtime check to satisfy the compiler — raise it to the maintainer instead.
swift build -c release

# 4. Package (assembles the .app: Sparkle framework, icon, menubar glyphs, helper; ad-hoc signs by default)
./Scripts/make-app.sh

# 5. Install + smoke test
rm -rf /Applications/NeverSleep.app && ditto .build/app/NeverSleep.app /Applications/NeverSleep.app
open /Applications/NeverSleep.app
# smoke test: toggle "Keep awake with lid closed", close the lid, reopen it — the session must still be live
#             (audio/video calls keep running with the screen off). Then quit the app and verify sleep behaves
#             exactly as before quitting.
```

Universal binary (Intel + Apple Silicon in one app). SwiftPM ≥ 5.6 handles both arches in one go; on an older toolchain, build each arch and `lipo`-join instead:

```bash
# one-shot (preferred):
swift build -c release --arch arm64 --arch x86_64

# fallback (older toolchain):
swift build -c release --arch arm64  && cp -r .build/arm64-apple-macosx/release build/opt/arm64
swift build -c release --arch x86_64 && cp -r .build/x86_64-apple-macosx/release build/opt/x86_64
lipo -create build/opt/arm64/NeverSleep build/opt/x86_64/NeverSleep -output build/NeverSleep-universal
```

*p.s. the built-in macOS shortcut to lock the screen by hand is `Control-Command-Q`.*

### What the build must NOT do

- Distribution: `scripts/make-dmg.sh <version> "Developer ID"` builds the notarized + stapled DMG that GitHub Releases ship, and `scripts/make-appcast.sh <version>` refreshes the self-update feed (Sparkle: startup + weekly checks, auto-install). Without the Developer ID identity everything falls back to ad-hoc — see `KB.md` "Build & test".
- No ci.yml, no Playwright, no worktrees: plain `swift build` on `main`.

