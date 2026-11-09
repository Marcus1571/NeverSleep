import Foundation

enum ShellRunner {
    /// Runs /usr/bin/pmset synchronously, capturing stdout/stderr. Never assumes
    /// success by exit code alone — the caller verifies by reading state back.
    static func run(_ launchPath: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do { try task.run() } catch {
            Log.error("failed to launch \(launchPath): \(error)")
            return (-1, "", "\(error)")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus,
                String(decoding: outData, as: UTF8.self),
                String(decoding: errData, as: UTF8.self))
    }
}
