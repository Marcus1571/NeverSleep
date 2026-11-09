import Foundation

/// User-facing settings, mirroring the NoSleep pane (parity contract in KB.md).
/// Persistence: UserDefaults is durable across app restarts; sleep-state
/// restoration is behavioral (baseline at quit), not a persisted flag.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var suppressOnAC: Bool {
        didSet { defaults.set(suppressOnAC, forKey: Keys.suppressOnAC) }
    }
    @Published var suppressOnBattery: Bool {
        didSet { defaults.set(suppressOnBattery, forKey: Keys.suppressOnBattery) }
    }
    @Published var useBlackWhiteIcons: Bool {
        didSet { defaults.set(useBlackWhiteIcons, forKey: Keys.useBlackWhiteIcons) }
    }
    @Published var launchAtLogin: Bool {
        didSet { LoginItem.set(enabled: launchAtLogin) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let suppressOnAC = "suppressOnAC"
        static let suppressOnBattery = "suppressOnBattery"
        static let useBlackWhiteIcons = "useBlackWhiteIcons"
        static let launchAtLogin = "launchAtLogin"
    }

    init(defaults: UserDefaults = .standard) {
        suppressOnAC = defaults.object(forKey: Keys.suppressOnAC) as? Bool ?? false
        suppressOnBattery = defaults.object(forKey: Keys.suppressOnBattery) as? Bool ?? false
        useBlackWhiteIcons = defaults.object(forKey: Keys.useBlackWhiteIcons) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    }

    /// Target for the power source we are on right now (NoSleep's
    /// per-source independence, minus the version-specific storage).
    func targetFor(powerSource: PowerSource) -> Bool? {
        switch powerSource {
        case .ac: return suppressOnAC
        case .battery: return suppressOnBattery
        case .unknown: return nil
        }
    }
}

/// Start-at-login via a LaunchAgent plist: works identically on macOS 11..26+,
/// no framework calls, survives reboots. Replaced by SMAppService on v2 if
/// it turns out to matter.
enum LoginItem {
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/app.legba.neversleep.plist")
    }

    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func set(enabled: Bool) {
        let url = plistURL
        if !enabled {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
                Log.info("login item removed")
            }
            return
        }
        let appPath = Bundle.main.bundleURL.path
        guard appPath.hasSuffix(".app") else {
            Log.error("login item: not running from a .app bundle (\(appPath)); cannot install LaunchAgent")
            return
        }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>app.legba.neversleep</string>
          <key>ProgramArguments</key><array><string>\(appPath)/Contents/MacOS/NeverSleep</string></array>
          <key>RunAtLoad</key><true/>
        </dict></plist>
        """
        do {
            try plist.write(to: url, atomically: true, encoding: .utf8)
            Log.info("login item installed at \(url.path)")
        } catch {
            Log.error("login item install failed: \(error)")
        }
    }
}
