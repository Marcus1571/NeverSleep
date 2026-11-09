import Foundation
import os

/// Rich logging: every attempt, input that matters, timing, and the specific
/// outcome/error — written to os_log AND ~/Library/Logs/NeverSleep.log.
enum Log {
    private static let osLog = Logger(subsystem: "app.legba.neversleep", category: "runtime")
    private static let fileURL: URL? = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Logs/NeverSleep.log")

    static func info(_ msg: String) { write(msg, level: "INFO") }
    static func error(_ msg: String) { write(msg, level: "ERROR") }

    private static func write(_ msg: String, level: String) {
        let line = "[\(DateFormatter.logStamp())] [\(level)] \(msg)"
        if level == "ERROR" { osLog.error("\(msg, privacy: .public)") } else { osLog.info("\(msg, privacy: .public)") }
        guard let url = fileURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(data: Data((line + "\n").utf8))
            try? handle.close()
        }
    }
}

private extension DateFormatter {
    static func logStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
