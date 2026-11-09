import Foundation

/// Represents parsed `pmset -g` output. Keys are exactly the strings pmset emits.
struct PowerState: Equatable {
    let values: [String: String]

    /// "SleepDisabled" from the system-wide section. nil = key unknown on this build.
    var sleepDisabled: Int? {
        values["SleepDisabled"].flatMap(Int.init)
    }
    var displaysSleep1minute: Int? { values["sleep"].flatMap(Int.init) }

    static func parse(_ text: String) -> PowerState {
        var values: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Lines look like:  " key                 value" (system-wide has a leading space, version ≥ 11)
            guard let spaceIndex = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let key = String(line[..<spaceIndex])
            let remainder = line[line.index(after: spaceIndex)...].trimmingCharacters(in: .whitespaces)
            if key.isEmpty || remainder.isEmpty { continue }
            if values[key] == nil { values[key] = remainder }
        }
        return PowerState(values: values)
    }
}
