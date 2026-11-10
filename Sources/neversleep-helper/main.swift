import Foundation
import Darwin

// neversleep-helper — root LaunchDaemon for NeverSleep.
//
// Installed once by the app (a single admin prompt writes this binary to
// /Library/PrivilegedHelperTools plus a LaunchDaemon plist, then bootstraps
// it). From then on the NeverSleep app (and neversleepctl) ask this daemon
// over a local unix socket to perform the one privileged job the product
// needs: `pmset [-b|-a] disablesleep 0|1`. No shell, fixed argv, peer-UID
// check, read-back verification, every attempt logged.
//
// Protocol (one request per connection, newline-terminated, reply + close):
//   PING                -> OK neversleep-helper/<version>
//   SET <scope> <value> -> OK | ERR exit=<n> | ERR verify
//     scope: -b or -a; value: 0 or 1 (anything else is a protocol error)
//   anything else       -> ERR protocol

let helperVersion = 2
let logPath = "/Library/Logs/NeverSleepHelper.log"
let pmsetPath = "/usr/bin/pmset"
let maxRequestBytes = 256

func log(_ s: String) {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let line = "[\(df.string(from: Date()))] [INFO] \(s)\n"
    if (try? FileManager.default.attributesOfItem(atPath: logPath)[.size] as? Int) ?? 0 > 1_000_000 {
        try? FileManager.default.removeItem(atPath: logPath)
    }
    if !FileManager.default.fileExists(atPath: logPath) {
        FileManager.default.createFile(atPath: logPath, contents: nil)
    }
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        h.closeFile()
    }
}

struct Config {
    var socketPath: String
    var allowUID: uid_t
}

func parseArgs() -> Config? {
    var socketPath: String?
    var allowUID: uid_t?
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let flag = it.next() {
        switch flag {
        case "--socket": socketPath = it.next()
        case "--allow-uid": allowUID = it.next().flatMap { uid_t($0) }
        default: log("unknown argument \(flag)"); return nil
        }
    }
    guard let sp = socketPath, let uid = allowUID else { return nil }
    return Config(socketPath: sp, allowUID: uid)
}

/// Parses `pmset -g` output for the SleepDisabled value. The label is
/// separated from the value by whitespace (tabs in the wild) — v0.3.1 and
/// earlier matched a literal "SleepDisabled 1" with a space and mis-verified
/// every write of 1 (the write worked; the daemon disbelieved it). Absent
/// label means 0 (verified macOS 27). Returns nil only when the output is
/// unrecognizable.
func sleepDisabledValue(in output: String) -> Int? {
    guard let range = output.range(of: "sleepdisabled", options: .caseInsensitive) else {
        return nil   // absent = 0
    }
    var rest = output[range.upperBound...]
    while let first = rest.first, first == "=" || first.isWhitespace {
        rest = rest.dropFirst()
    }
    guard let first = rest.first, first.isNumber, let value = first.wholeNumberValue, (0...9).contains(value) else {
        return nil
    }
    return value
}

/// Runs /usr/bin/pmset with fixed argv (no shell, no interpolation beyond the
/// validated scope/value tokens) and verifies the effect by reading `pmset -g`
/// back — same ground truth the app itself uses.
func performSet(_ scope: String, _ value: String, uid: uid_t) -> String {
    let t0 = Date()
    guard let target = Int(value) else { return "ERR protocol" }
    func run(_ arguments: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pmsetPath)
        p.arguments = arguments
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch {
            return (-1, "\(error)")
        }
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    let (exit, err) = run([scope, "disablesleep", value])
    var verified = false
    var parsed: Int?
    if exit == 0 {
        let (vExit, vOut) = { () -> (Int32, String) in
            let v = Process()
            v.executableURL = URL(fileURLWithPath: pmsetPath)
            v.arguments = ["-g"]
            let o = Pipe(), e = Pipe()
            v.standardOutput = o
            v.standardError = e
            do { try v.run() } catch { return (-1, "\(error)") }
            let data = o.fileHandleForReading.readDataToEndOfFile()
            v.waitUntilExit()
            return (v.terminationStatus, String(decoding: data, as: UTF8.self))
        }()
        parsed = vExit == 0 ? sleepDisabledValue(in: vOut) : nil
        verified = parsed == target
    }
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    log("SET \(scope) disablesleep \(value) uid=\(uid) exit=\(exit) verified=\(verified) parsed=\(parsed.map(String.init) ?? "unrecognized") took=\(ms)ms stderr=\(err)")
    if exit != 0 { return "ERR exit=\(exit)" }
    if !verified { return "ERR verify" }
    return "OK"
}

func handle(clientFD: Int32, uid: uid_t) -> String {
    var buf = [UInt8](repeating: 0, count: maxRequestBytes)
    var got = 0
    while got < maxRequestBytes {
        let n = recv(clientFD, &buf + got, maxRequestBytes - got, 0)
        if n <= 0 { break }
        got += n
        if buf[0..<got].contains(UInt8(ascii: "\n")) { break }
    }
    let request = String(decoding: buf[0..<got], as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = request.split(separator: " ").map(String.init)
    switch (parts.first, parts.count) {
    case ("PING", 1):
        return "OK neversleep-helper/\(helperVersion)"
    case ("SET", 3):
        guard ["-b", "-a"].contains(parts[1]), ["0", "1"].contains(parts[2]) else {
            log("denied malformed SET uid=\(uid): '\(request)'")
            return "ERR protocol"
        }
        return performSet(parts[1], parts[2], uid: uid)
    default:
        log("denied unknown request uid=\(uid): '\(request)'")
        return "ERR protocol"
    }
}

signal(SIGPIPE, SIG_IGN)   // a client vanishing mid-reply must not kill the daemon

guard let cfg = parseArgs() else {
    log("fatal: expected --socket <path> --allow-uid <uid>")
    exit(2)
}

// Fresh socket file each start: a leftover from a crashed run must not wedge
// the bind. (bootout/bootstrap in the installer ensures a single instance.)
unlink(cfg.socketPath)

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { log("fatal: socket() failed errno=\(errno)"); exit(1) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(cfg.socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
    log("fatal: socket path too long (\(cfg.socketPath))")
    exit(2)
}
withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: pathBytes) }

let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard bound == 0 else {
    log("fatal: bind(\(cfg.socketPath)) failed errno=\(errno)")
    exit(1)
}
guard listen(fd, 4) == 0 else {
    log("fatal: listen failed errno=\(errno)")
    exit(1)
}
// 0666 on the socket + the getpeereid() UID check below is the access model:
// any local process may connect, only the installing user's requests run.
chmod(cfg.socketPath, 0o666)

log("started: socket=\(cfg.socketPath) allow-uid=\(cfg.allowUID) version=\(helperVersion)")

while true {
    let client = accept(fd, nil, nil)
    guard client >= 0 else {
        log("accept failed errno=\(errno)")
        continue
    }
    var peerUID: uid_t = 0
    var peerGID: gid_t = 0
    guard getpeereid(client, &peerUID, &peerGID) == 0 else {
        log("denied: getpeereid failed errno=\(errno)")
        close(client)
        continue
    }
    guard peerUID == cfg.allowUID else {
        log("denied: peer uid=\(peerUID) not allowed (allowed: \(cfg.allowUID))")
        close(client)
        continue
    }
    let reply = handle(clientFD: client, uid: peerUID)
    let data = Data((reply + "\n").utf8)
    data.withUnsafeBytes { raw in
        _ = send(client, raw.baseAddress, raw.count, 0)
    }
    close(client)
}
