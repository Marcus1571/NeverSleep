import Foundation
import ServiceManagement

/// User-facing settings, mirroring the NoSleep pane (parity contract in KB.md).
/// Persistence: UserDefaults is durable across app restarts; sleep-state
/// restoration is behavioral (baseline at quit), not a persisted flag.
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    @Published public var suppressOnAC: Bool {
        didSet { defaults.set(suppressOnAC, forKey: Keys.suppressOnAC) }
    }
    @Published public var suppressOnBattery: Bool {
        didSet { defaults.set(suppressOnBattery, forKey: Keys.suppressOnBattery) }
    }
    @Published public var useBlackWhiteIcons: Bool {
        didSet { defaults.set(useBlackWhiteIcons, forKey: Keys.useBlackWhiteIcons) }
    }
    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin); LoginItem.set(enabled: launchAtLogin) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let suppressOnAC = "suppressOnAC"
        static let suppressOnBattery = "suppressOnBattery"
        static let useBlackWhiteIcons = "useBlackWhiteIcons"
        static let launchAtLogin = "launchAtLogin"
    }

    public init(defaults: UserDefaults = .standard) {
        suppressOnAC = defaults.object(forKey: Keys.suppressOnAC) as? Bool ?? false
        suppressOnBattery = defaults.object(forKey: Keys.suppressOnBattery) as? Bool ?? false
        useBlackWhiteIcons = defaults.object(forKey: Keys.useBlackWhiteIcons) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        // Adopt the live truth when it drifted from the stored default (e.g. the
        // login item was turned off in System Settings, or on before this ran).
        // Never auto-registers on launch: first-order divergence from "off" to
        // "on" happens only through an explicit user action.
        if LoginItem.isEnabled() != launchAtLogin {
            launchAtLogin = LoginItem.isEnabled()
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    /// Target for the power source we are on right now (NoSleep's
    /// per-source independence, minus the version-specific storage).
    public func targetFor(powerSource: PowerSource) -> Bool? {
        switch powerSource {
        case .ac: return suppressOnAC
        case .battery: return suppressOnBattery
        case .unknown: return nil
        }
    }
}

/// Start-at-login, dotbar's mechanism (KB parity item 7): `SMAppService.mainApp`
/// registers the installed bundle as a login item — visible and reversible in
/// System Settings › General › Login Items, survives app path moves. This is the
/// live source of truth; the LaunchAgent plist below stays only as the fallback
/// for macOS 11–12, where ServiceManagement's modern API does not exist.
/// SMAppService itself is macOS 13+.
public enum LoginItem {
    public static func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    public static func set(enabled: Bool) {
        if #available(macOS 13.0, *) {
            let s = SMAppService.mainApp
            do {
                try enabled ? s.register() : s.unregister()
                Log.info("login item \(enabled ? "registered" : "unregistered") via SMAppService (status \(s.status.rawValue))")
            } catch {
                Log.error("login item SMAppService \(enabled ? "register" : "unregister") failed: \(error)")
            }
            return
        }
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

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/app.legba.neversleep.plist")
    }
}
