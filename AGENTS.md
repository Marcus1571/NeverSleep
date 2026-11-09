# AGENTS.md

Read `GOVERNANCE.md` and `USER.md` from their working copy (the operator's private `governance` GitHub repository — see `GOVERNANCE.md`'s "The two fixed, universal files" section) at the start of any session in this project; they hold the operator's cross-project defaults. This file governs when those two disagree on a project-specific fact — general defaults yield to this project's own documented specifics, except cross-cutting principles (secrets handling, destructive-action caution, and the like) which still apply everywhere regardless of project.

## What this project is

NeverSleep is a macOS menu-bar app that keeps a MacBook fully awake with the lid closed, as a modern replacement for the deprecated kext-based NoSleep. The user-facing feature contract it must live up to is documented exhaustively in `KB.md`("Feature contract from NoSleep"). The technical approach is documented in `KB.md`"Approach" and the decision trail in `findings.md`; do not re-litigate a decided approach after this session without a materially new fact (a macOS update changing what works, a user report, etc.).

## How to work here

- **No new code side experiments in parallel**: `STATUS.md` is the truth on what is in flight. Update it the same session you change anything.
- The doc-sync rule from `GOVERNANCE.md` applies to *any* real unit of work: before ending a session, `STATUS.md` (and `KB.md` if the design or claimed capabilities changed, `CHANGELOG.md` on releases) must reflect what actually happened.
- Old research and dead ends go to `findings.md` with a verdict — never into `README.md` or `KB.md` (KB gets only what the design *adopts*).
- `README.md` is a pitch. It names a representative few features and deep-links into KB; it never enumerates everything.

## Build / test reality

- Target: Swift + SwiftUI, app built in Xcode on the operator's Mac. No CI exists; nothing here is testable on a Linux box — a session running somewhere else must not claim behavior was verified, only that code compiles if it compiles somewhere real.
- Toggling sleep suppression requires admin privileges (a privileged helper or an equivalent auth flow). Never fake raw `sudo pmset` output based on an assumption; run it on the Mac.
- Minimum supported macOS versions: decide before the first tagged release and record in `KB.md`; until then macOS 13+ is the assumed floor.

## License

MIT for code (`LICENSE`), with the derived art under GPL-2.0 (`art/ART-LICENSE.md`) inherited from the original NoSleep assets. Keep the two file families separated accordingly: do not move art into `Sources/` as if it were permissively licensed.
