import Foundation
import IOKit

/// Display control for the lid-closed-but-awake state (KB "Display behavior").
///
/// `pmset disablesleep` keeps the system awake with the lid closed, but —
/// observed live on macOS 27 / M3 — macOS does NOT blank the internal panel
/// on its own in that state: the display stayed lit with the lid shut.
/// NeverSleep blanks it explicitly, through the **display sleep** path only:
/// display sleep is the system's own display-idle mechanism and never pauses
/// apps, audio or network — the "exactly like an open lid, minus the screen"
/// contract, with zero effect on running services.
///
/// The one hard rule: when an external display is attached, displays are
/// never touched — lid-closed-with-external is clamshell working mode (the
/// external screen is in active use), not a blankable state.
public enum DisplayControl {
    /// True while at least one external panel is present in the display
    /// tree. Detected via AppleDisplayConnectionManager's `ConnectionMapping`
    /// entries (`role = DCPEXT` — the Apple Silicon display-coprocessor
    /// registry truth; verified live with a DELL P3424WEB attached, and no
    /// DCPEXT entry while only the built-in panel would be in play).
    /// `CGDisplayIsBuiltin` alone is not trusted after it reported the
    /// built-in panel class inconsistently on this build. No mapping service
    /// on non-Apple-Silicon machines → conservatively reported as "no
    /// external" so the blanking path still works there.
    public static func externalDisplayAttached() -> Bool {
        let manager = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleDisplayConnectionManager"))
        guard manager != 0 else { return false }
        defer { IOObjectRelease(manager) }
        guard let raw = IORegistryEntrySearchCFProperty(
            manager, kIOServicePlane,
            "ConnectionMapping" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)) else { return false }
        guard let mapping = raw as? [Any] else { return false }
        return mapping.contains { ($0 as? [String: Any])?["role"] as? String == "DCPEXT" }
    }

    /// Sleeps the display(s) now — equivalent to the display-sleep timer
    /// firing early. Runs off the main thread (the command is synchronous
    /// but fast; the wake helper below is not). Unprivileged (verified:
    /// exit 0 as the console user).
    public static func sleepNow() {
        DispatchQueue.global(qos: .utility).async {
            let (code, _, err) = ShellRunner.run("/usr/bin/pmset", arguments: ["displaysleepnow"])
            if code != 0 {
                Log.error("pmset displaysleepnow failed exit=\(code) stderr=\(err.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                Log.info("display put to sleep (lid closed while suppressed)")
            }
        }
    }

    /// Wakes the display(s) with the same user-activity signal the system
    /// uses on real input (`caffeinate -u`). Harmless when the display
    /// already woke natively on lid open — always run it, so the wake never
    /// depends on unverified native behavior.
    public static func wake() {
        DispatchQueue.global(qos: .utility).async {
            let (code, _, err) = ShellRunner.run("/usr/bin/caffeinate", arguments: ["-u", "-t", "2"])
            if code != 0 {
                Log.error("caffeinate -u failed exit=\(code) stderr=\(err.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                Log.info("display wake asserted (lid opened)")
            }
        }
    }
}
