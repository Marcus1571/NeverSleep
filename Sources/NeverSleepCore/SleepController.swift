import Foundation

/// Core sleep-suppression engine.
///
/// Mechanism: `pmset disablesleep 0|1`. Apple ships the same pmset across
/// macOS 10.13+, Intel and Apple Silicon; nothing here branches by OS version
/// or architecture — anything the running build refuses is detected by reading
/// results back, not hardcoded knowledge.
///
/// Privilege note: pmset writes need root. In v1 every write goes through one
/// system auth dialog (osascript "with administrator privileges"); reads don't.
public final class SleepController {
    public enum Outcome: Equatable {
        case enabled(scope: String)
        case disabled(scope: String)
        case alreadyEnabled(scope: String)
        case alreadyDisabled
        case failed(reason: String)

        public var userMessage: String {
            switch self {
            case .enabled(let scope): return "Sleep suppressed (\(scope)). Mac stays awake with the lid closed."
            case .disabled(let scope): return "Normal macOS sleep restored (\(scope))."
            case .alreadyEnabled(let scope): return "Already suppressed (\(scope))."
            case .alreadyDisabled: return "Sleep already normal."
            case .failed(let reason): return "pmset failed: \(reason)"
            }
        }
    }

    public struct Baseline: Equatable { public let sleepDisabled: Int? }

    private let pmsetPath = "/usr/bin/pmset"
    private let admin: AdminPrivileges
    private(set) var prefersBatteryScopedKey = true
    public private(set) var baseline: Baseline?

    public init(admin: AdminPrivileges = .shared) {
        self.admin = admin
    }

    // MARK: Reading (unprivileged)

    @discardableResult
    public func readState() -> PowerState? {
        let (code, out, err) = ShellRunner.run(pmsetPath, arguments: ["-g"])
        guard code == 0 else {
            Log.error("pmset -g failed exit=\(code) stderr=\(err.trimmingCharacters(in: .whitespacesAndNewlines))")
            return nil
        }
        let state = PowerState.parse(out)
        Log.info("read state: SleepDisabled=\(state.sleepDisabled.map(String.init) ?? "unknown")")
        return state
    }

    // MARK: Baseline

    public func captureBaseline() {
        let state = readState()
        baseline = state.map { Baseline(sleepDisabled: $0.sleepDisabled) }
        Log.info("baseline captured: \(String(describing: baseline))")
    }

    public func restoreBaseline() {
        guard let baseline = baseline else {
            Log.info("restoreBaseline: no baseline captured, nothing to do")
            return
        }
        let target = baseline.sleepDisabled ?? 0
        // No write (and no admin prompt) when nothing changed — quit runs this twice.
        if readState()?.sleepDisabled == target {
            Log.info("restoreBaseline: already at baseline SleepDisabled=\(target)")
            return
        }
        Log.info("restoring baseline SleepDisabled=\(target)")
        _ = writeDisablesleep(target)
    }

    // MARK: Motate

    public func setSleepSuppressed(_ suppress: Bool) -> Outcome {
        let target = suppress ? 1 : 0
        if let current = readState()?.sleepDisabled, current == target {
            let scope = prefersBatteryScopedKey ? "battery-scoped (-b)" : "system-wide (-a)"
            return suppress ? .alreadyEnabled(scope: scope) : .alreadyDisabled
        }
        guard let (_, scope) = writeDisablesleep(target) else {
            return .failed(reason: "pmset rejected disablesleep=\(target) in all scopes")
        }
        if let verified = readState()?.sleepDisabled, verified == target {
            Log.info("verified disablesleep=\(target) via \(scope)")
            return suppress ? .enabled(scope: scope) : .disabled(scope: scope)
        }
        return .failed(reason: "pmset exited 0 but verification read did not match (target=\(target))")
    }

    private func writeDisablesleep(_ value: Int) -> (Bool, String)? {
        if prefersBatteryScopedKey {
            let args = "\(pmsetPath) -b disablesleep \(value)"
            if admin.runAsRoot(args) {
                let ok = readState()?.sleepDisabled == value
                if ok { return (true, "battery-scoped (-b)") }
                Log.error("-b write accepted but verification mismatched; trying -a")
            }
            Log.error("pmset -b disablesleep refused or ineffective, falling back to -a")
            prefersBatteryScopedKey = false
        }
        if admin.runAsRoot("\(pmsetPath) -a disablesleep \(value)") {
            return readState()?.sleepDisabled == value ? (true, "system-wide (-a)") : nil
        }
        return nil
    }
}

/// v1 privilege path: one auth dialog per write via osascript. Password never
/// passes through this app — the system dialog handles it.
public final class AdminPrivileges {
    public static let shared = AdminPrivileges()
    init(commandPath: String = "/usr/bin/osascript") { self.commandPath = commandPath }
    private let commandPath: String

    func runAsRoot(_ script: String) -> Bool {
        let appleScript = "do shell script \"\(script)\" with administrator privileges"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: commandPath)
        task.arguments = ["-e", appleScript]
        let errPipe = Pipe()
        task.standardOutput = Pipe()
        task.standardError = errPipe
        do { try task.run() } catch {
            Log.error("osascript could not start: \(error)")
            return false
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let stderrText = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        defer { if !stderrText.isEmpty { Log.error("osascript stderr: \(stderrText)") } }
        let ok = task.terminationStatus == 0
        if ok { Log.info("privileged run ok: \(script)") } else { Log.error("privileged run failed exit=\(task.terminationStatus): \(script)") }
        return ok
    }
}
