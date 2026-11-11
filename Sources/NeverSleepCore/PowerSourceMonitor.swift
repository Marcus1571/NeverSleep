import Foundation
import IOKit

/// Which power source is active, read from `pmset -g batt` (works across all
/// targeted macOS versions, no IOKit header wrangling, identical on Intel/ARM).
public enum PowerSource: String {
    case battery = "Battery Power"
    case ac = "AC Power"
    case unknown = "Unknown"
}

public enum PowerSourceReader {
    public static func current() -> PowerSource {
        let (code, out, _) = ShellRunner.run("/usr/bin/pmset", arguments: ["-g", "batt"])
        guard code == 0 else { return .unknown }
        if out.contains("'\(PowerSource.ac.rawValue)'") { return .ac }
        if out.contains("'\(PowerSource.battery.rawValue)'") { return .battery }
        return .unknown
    }
}

/// Lid state via IOPMrootDomain's "AppleClamshellState" property. Verified
/// live on macOS 27 / M3 (2026-11-11): AppleSmartBattery carries NO clamshell
/// keys on this build; IOPMrootDomain's AppleClamshellState tracks the lid
/// live (Yes observed with the lid closed, AppleClamshellCausesSleep=No while
/// disablesleep is set). Public IORegistry read; same path on Intel and
/// Apple Silicon. Returns nil when the machine has no lid signal (desktops) —
/// the caller treats nil as "unknown", never as "closed".
public enum LidState {
    public static func isClosed() -> Bool? {
        let domain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard domain != 0 else { return nil }
        defer { IOObjectRelease(domain) }
        guard let raw = IORegistryEntrySearchCFProperty(
            domain, kIOServicePlane,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively))
        else { return nil }
        return raw as? Bool
    }
}
