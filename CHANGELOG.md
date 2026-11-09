# CHANGELOG

All notable changes. Format: Keep a Changelog-ish, versioned per the release sequence in `USER.md`.

## [0.1.0] — 2026-11-09

- Project founded; public repo created (`Marcus1571/NeverSleep`).
- Research complete: original NoSleep located (repo + MacUpdate page), full feature map extracted from its source, mechanisms for modern macOS identified; findings in `findings.md`, adopted design in `KB.md`.
- Recolored "Zz" icon derivative shipped under `art/` (app icon + two menu-bar states, recolored per the operator's request; GPL-2.0 inherited, `art/ART-LICENSE.md`).
- Governance layer installed (`README`, `AGENTS`, `STATUS`, `findings`, `KB`, this file) per the operator's two-backup git flow.
- No app code yet — see `STATUS.md` for the ordered plan.

- **v0.1.0 code baseline written** (uncommitted state → now committed): SPM Package.swift, `NeverSleep`/`NeverSleepCore`/`neversleepctl` sources, `Scripts/make-bundle.sh` + `Scripts/make-iconset.sh`.
- Design rule: one code path, macOS 11.0 floor, `NSStatusItem` UI (not `MenuBarExtra`), runtime probing of `pmset` capabilities with `-b`/`-a` fallback and post-write verification; never touches an already-`SleepDisabled 1` machine.
