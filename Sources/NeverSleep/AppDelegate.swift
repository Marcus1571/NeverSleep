import AppKit
import SwiftUI
import Combine
import Sparkle
import NeverSleepCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = SleepController()
    private let settings = SettingsStore.shared
    private var statusBar: StatusBarController!
    private var prefsWindow: NSWindow?
    private var menuUpdater: AnyCancellable?
    private var lastKnownPowerSource: PowerSource = .unknown
    // Sparkle: nil for bare-binary launches (Sparkle can only update a bundled app).
    private var updaterController: SPUStandardUpdaterController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Log.info("launched: build=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?"))")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One-time privileged-helper offer: when the first privileged write is
        // needed and no helper is installed, show what installing means and
        // get the single confirmation. Declining keeps the v1 per-write
        // osascript prompts. Only meaningful when running from the installed
        // bundle (the helper binary ships inside it).
        if Bundle.main.bundlePath.hasSuffix(".app") {
            AdminPrivileges.shared.helperInstallOffer = { [weak self] in
                self?.offerHelperInstall() ?? false
            }
        }
        Log.info("privileged helper: \(PrivilegedHelper.handshake() ?? "not installed (will be offered on first toggle)")")
        // Safety gate: if the machine is already permanently awake (e.g. a
        // deliberate SleepDisabled 1 config), do not touch anything — warn only.
        if let state = controller.readState(), state.sleepDisabled == 1, controller.baseline == nil {
            controller.captureBaseline()
            if controller.baseline?.sleepDisabled == 1 {
                Log.info("machine already permanently suppressed; staying read-only")
                statusBar = StatusBarController(settings: settings,
                                                onToggle: { [weak self] on in self?.handleToggle(on) },
                                                onOpenPrefs: { [weak self] in self?.openPreferences() },
                                                onQuit: { [weak self] in self?.quitClean() },
                                                updater: nil,
                                                externallySuppressed: true)
                return
            }
        }
        controller.captureBaseline()
        // Sparkle scheduler comes from Info.plist (check at startup, weekly
        // interval); only when running from a bundle — bare `swift run` has
        // nothing to update. NeverSleep installs a root helper: a Sparkle
        // update swaps the app bundle, while the daemon keeps running the
        // version in /Library/PrivilegedHelperTools until the next helper
        // reinstall (handshake/protocol handles the drift — see KB).
        if Bundle.main.bundlePath.hasSuffix(".app") {
            updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                             updaterDelegate: nil,
                                                             userDriverDelegate: nil)
        }
        statusBar = StatusBarController(settings: settings,
                                        onToggle: { [weak self] on in self?.handleToggle(on) },
                                        onOpenPrefs: { [weak self] in self?.openPreferences() },
                                        onQuit: { [weak self] in self?.quitClean() },
                                        updater: updaterController,
                                        externallySuppressed: false)
        pollPowerSource(initial: true)
        schedulePowerSourcePolling()
    }

    private func schedulePowerSourcePolling() {
        // 5s poll — simple and version-agnostic; richer IOKit notifications land in v0.2.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.pollPowerSource(initial: false)
            self?.schedulePowerSourcePolling()
        }
    }

    private func pollPowerSource(initial: Bool) {
        let source = PowerSourceReader.current()
        guard source != lastKnownPowerSource || initial else { return }
        Log.info("power source: \(source.rawValue) (was \(lastKnownPowerSource.rawValue))")
        lastKnownPowerSource = source
        statusBar.update(powerSource: source, active: desiredActive())
    }

    /// What the settings say for the current power source.
    private func desiredActive() -> Bool {
        settings.targetFor(powerSource: lastKnownPowerSource) ?? false
    }

    private func offerHelperInstall() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Install the NeverSleep helper?"
        alert.informativeText = "NeverSleep can install a tiny privileged helper (it runs as root and only ever flips the sleep setting). This is the last password you will ever type for NeverSleep — after it, toggling, quitting and restoring never ask again.\n\nIf you decline, NeverSleep keeps asking for the password on every toggle."
        alert.addButton(withTitle: "Install Helper")
        alert.addButton(withTitle: "Ask Each Time")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func handleToggle(_ on: Bool) {
        let source = lastKnownPowerSource
        Log.info("user toggle: on=\(on) source=\(source.rawValue)")
        guard settings.targetFor(powerSource: source) != nil || on else {
            Log.info("toggle ignored: no suppression configured for \(source.rawValue)")
            return
        }
        let outcome = controller.setSleepSuppressed(on)
        Log.info("toggle result: \(outcome.userMessage)")
        if case .failed(let reason) = outcome {
            let alert = NSAlert()
            alert.messageText = "NeverSleep"
            alert.informativeText = reason
            alert.runModal()
        }
        statusBar.refresh(active: on)
    }

    private func openPreferences() {
        if prefsWindow == nil {
            let prefs = PreferencesView(settings: settings)
            let window = NSWindow(contentViewController: NSHostingController(rootView: prefs))
            window.title = "NeverSleep Preferences"
            window.setContentSize(NSSize(width: 480, height: 340))
            window.center()
            prefsWindow = window
        }
        prefsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func quitClean() {
        controller.restoreBaseline()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreBaseline()   // belt + suspenders: quit path always restores
        Log.info("terminated, baseline restored")
    }
}
