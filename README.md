# NeverSleep

*Successor to [NoSleep](https://github.com/integralpro/nosleep) — close the lid, keep working.*

NeverSleep is a lean macOS menu-bar app that keeps a MacBook **fully awake with the lid closed**. Close the lid and keep talking on Teams / Zoom, keep a download running, keep a render going — the machine behaves exactly as if the lid were open, minus the display being on (the display turns itself off on its own; NeverSleep does not force it).

NoSleep solved this with a kernel extension, which modern macOS (SIP + user-approved kext loading) made unmaintainable; it was deprecated in ~2019. NeverSleep ships the same user-facing feature contract on the modern mechanism instead: a runtime toggle of the OS's own sleep-disable behavior ([KB.md — Approach](KB.md#approach)), applied only while NeverSleep runs and restored when it quits.

**What it does (v0 spec, representative — full contract in [KB.md — Feature contract](KB.md#feature-contract-from-nosleep)):**

- One menu-bar toggle (`Zz` icon, filled = awake): closes-the-lid sleep prevention, per power source
- Separate behavior on battery vs. AC, like NoSleep's two independent toggles
- Optional "require password on display opening" auto-lock when the lid closes
- State restored to normal macOS sleep behavior the moment the app quits

Read [STATUS.md](STATUS.md) for where development stands, and [findings.md](findings.md) for the research trail that led to the approach. The art works: it is a recolored derivative ([art/ART-LICENSE.md](art/ART-LICENSE.md)) — same "Zz" glyph as NoSleep, different color scheme so it is not a wholesale visual copy.

⚠️ A Mac awake with a closed lid has reduced cooling. NeverSleep is for use *while you are using the machine*, not for closed-lid tasks in a backpack all day.
