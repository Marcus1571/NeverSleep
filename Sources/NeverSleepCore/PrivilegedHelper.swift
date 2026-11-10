import Foundation

/// Client for the `neversleep-helper` root LaunchDaemon (see
/// Sources/neversleep-helper/main.swift for the protocol). The daemon performs
/// the one privileged operation NeverSleep needs — `pmset [-b|-a] disablesleep
/// 0|1` — so the app (and neversleepctl) never prompt for a password after the
/// helper's one-time install. Access model: local unix socket, daemon checks
/// the connecting peer UID, fixed argv inside the daemon, read-back verified.
public enum PrivilegedHelper {
    public static let socketPath = "/var/run/app.legba.neversleep.helper.sock"
    public static let label = "app.legba.neversleep.helper"
    public static let daemonBinaryPath = "/Library/PrivilegedHelperTools/app.legba.neversleep.helper"
    public static var launchdPlistPath: String { "/Library/LaunchDaemons/\(label).plist" }
    public static let protocolVersion = 1

    public enum CommandError: Error, Equatable {
        case notInstalled          // no daemon answering on the socket
        case refused(String)       // daemon answered ERR (write rejected / not verified)
    }

    // MARK: Socket plumbing

    /// One request, one reply, connection closed. Returns nil whenever the
    /// helper is absent, wedged, or slow — callers treat nil as "no helper".
    private static func transact(_ request: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: pathBytes) }

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        // Never hang the UI on a wedged daemon: 3 s on every socket op.
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let payload = Data((request + "\n").utf8)
        let sent = payload.withUnsafeBytes { raw -> Int in
            send(fd, raw.baseAddress, raw.count, 0)
        }
        guard sent == payload.count else { return nil }

        var buf = [UInt8](repeating: 0, count: 1024)
        let n = recv(fd, &buf, buf.count, 0)
        guard n > 0 else { return nil }
        return String(decoding: buf[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Non-nil when a helper of the expected protocol version is answering.
    public static func handshake() -> String? {
        guard let reply = transact("PING") else { return nil }
        guard reply == "OK neversleep-helper/\(protocolVersion)" else { return nil }
        return reply
    }

    public static func pmset(scope: String, value: Int) -> Result<Void, CommandError> {
        guard let reply = transact("SET \(scope) \(value)") else { return .failure(.notInstalled) }
        if reply == "OK" { return .success(()) }
        return .failure(.refused(reply))
    }

    // MARK: Install / uninstall (root steps run via one osascript admin prompt)

    /// Installs the helper: copies the bundled binary to
    /// /Library/PrivilegedHelperTools (root-owned — the app bundle stays
    /// user-writable and must never be executed as root), writes the
    /// LaunchDaemon plist, and bootstraps it. `runAsRoot` receives a plain
    /// single-line shell script and runs it with one admin prompt. Waits up to
    /// 5 s for the daemon to answer before declaring success.
    public static func install(runAsRoot: (String) -> Bool) -> Bool {
        guard let resources = Bundle.main.resourceURL else {
            Log.error("helper install: not running from a bundle")
            return false
        }
        let bundled = resources.appendingPathComponent("neversleep-helper").path
        guard FileManager.default.fileExists(atPath: bundled) else {
            Log.error("helper install: bundled helper missing at \(bundled)")
            return false
        }

        let uid = getuid()
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>\(label)</string>
          <key>ProgramArguments</key><array>
            <string>\(daemonBinaryPath)</string>
            <string>--socket</string><string>\(socketPath)</string>
            <string>--allow-uid</string><string>\(uid)</string>
          </array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
        </dict></plist>
        """
        let tmpPlist = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label).plist")
        do { try plist.write(to: tmpPlist, atomically: true, encoding: .utf8) } catch {
            Log.error("helper install: staging plist failed: \(error)")
            return false
        }
        defer { try? FileManager.default.removeItem(at: tmpPlist) }

        // Single-line script (osascript "do shell script" round-trips it to
        // root sh). File steps chain with &&; the two launchctl steps run
        // unconditionally after them — bootout exits non-zero when the service
        // is not loaded (first install) and must not stop the bootstrap (that
        // exact bug silently killed v0.3.0 installs).
        let script = [
            "mkdir -p /Library/PrivilegedHelperTools",
            "cp -f '\(bundled)' \(daemonBinaryPath)",
            "chown root:wheel \(daemonBinaryPath)",
            "chmod 0755 \(daemonBinaryPath)",
            "cp -f '\(tmpPlist.path)' \(launchdPlistPath)",
            "chown root:wheel \(launchdPlistPath)",
            "chmod 0644 \(launchdPlistPath)",
        ].joined(separator: " && ")
            + "; launchctl bootout system/\(label) >/dev/null 2>&1; launchctl bootstrap system \(launchdPlistPath)"

        Log.info("helper install: requesting one admin prompt")
        guard runAsRoot(script) else {
            Log.error("helper install: root script failed (declined or errored)")
            return false
        }
        for _ in 0..<20 {
            if handshake() != nil {
                Log.info("helper installed and answering on \(socketPath)")
                return true
            }
            usleep(250_000)
        }
        Log.error("helper installed but not answering after 5 s (launchctl/daemon problem — see \(launchdPlistPath))")
        return false
    }

    /// Manual removal (documented in KB.md; no in-app UI — this helper is
    /// meant to stay):
    ///   sudo launchctl bootout system/app.legba.neversleep.helper
    ///   sudo rm -f /Library/LaunchDaemons/app.legba.neversleep.helper.plist
    ///              /Library/PrivilegedHelperTools/app.legba.neversleep.helper
    ///              /var/run/app.legba.neversleep.helper.sock
}
