import Foundation

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

/// Lid state via the IORegistry "AppleClamshellState" property on
/// "AppleSmartBattery". Public IORegistry read; same path on Intel and Apple
/// Silicon. Returns nil when the build cannot read it (e.g. desktops) — the
/// caller treats nil as "unknown", never as "closed".
enum LidState {
    static func isClosed() -> Bool? {
        nil // replaced by IOKit read once it compiles on-device (see STATUS open item)
    }
}
