import Foundation
import NeverSleepCore

// neversleepctl: script flipper mirroring NoSleepCtrl's role.
//   neversleepctl status        -> current SleepDisabled value + whether we are the one that set it
//   neversleepctl suppress      -> enable sleep suppression (admin prompt)
//   neversleepctl restore       -> disable suppression
let args = CommandLine.arguments.dropFirst()
let controller = SleepController()
guard let command = args.first else {
    print("usage: neversleepctl status|suppress|restore")
    exit(2)
}
switch command {
case "status":
    if let state = controller.readState() {
        print("SleepDisabled: \(state.sleepDisabled.map(String.init) ?? "unknown")")
        print("power source : \(PowerSourceReader.current().rawValue)")
    } else {
        print("pmset -g unreadable")
        exit(1)
    }
case "suppress", "restore":
    let result = controller.setSleepSuppressed(command == "suppress")
    print(result.userMessage)
    exit(result.isFailure ? 1 : 0)
default:
    print("unknown command: \(command)")
    exit(2)
}
