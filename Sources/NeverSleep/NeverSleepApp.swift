import AppKit

// NeverSleep — menu-bar app, no dock icon, SwiftUI preferences window.
// Entry point: NSApplication with NSStatusItem UI (works macOS 11..26+, Intel + Apple Silicon).

let appDel = AppDelegate()
let app = NSApplication.shared
app.delegate = appDel
app.setActivationPolicy(.accessory)   // menu-bar only, never an icon in the Dock
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
