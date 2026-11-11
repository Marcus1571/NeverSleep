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
    private var lastKnownActive = false
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
        // Startup state reconciliation. SleepDisabled=1 outlives this process
        // (survives crashes and reboots), so it is ambiguous: with the
        // ownership marker it is OUR leftover from an unclean death — adopt
        // it and keep the toggle live (baseline forced to 0, so quit still
        // restores). Without the marker it is a deliberate external config —
        // stay read-only, warn only, never touch it. (v0.4.0 captured its
        // own leftover as a baseline here, which locked the app read-only
        // forever and could never clear itself.)
        var externallySuppressed = false
        if controller.readState()?.sleepDisabled == 1 {
            if SleepController.SuppressionOwnership.isActiveSuppressionOurs {
                controller.adoptLeftoverSuppression()
            } else {
                controller.captureBaseline()
                if controller.baseline?.sleepDisabled == 1 {
                    externallySuppressed = true
                    Log.info("machine suppressed from outside NeverSleep; staying read-only")
                }
            }
        } else {
            controller.captureBaseline()
        }
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
                                        externallySuppressed: externallySuppressed)
        // The poll runs in every mode: the read-only path previously skipped
        // it, which froze the menu on "Power source: Unknown" (v0.4.0 bug).
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
        // The icon reflects the LIVE pmset state, not the preference: a
        // manual toggle or an external pmset change must show up here, and
        // the previous preference-based value could contradict the machine
        // (icon off while sleep was actually disabled).
        let liveActive = controller.isSleepSuppressed()
        guard source != lastKnownPowerSource || liveActive != lastKnownActive || initial else { return }
        Log.info("state: power=\(source.rawValue) suppressed=\(liveActive) (was power=\(lastKnownPowerSource.rawValue) suppressed=\(lastKnownActive))")
        lastKnownPowerSource = source
        lastKnownActive = liveActive
        statusBar.update(powerSource: source, active: liveActive)
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
        // Turning suppression OFF is always legitimate — restoring normal
        // sleep must never be blocked by a missing per-source preference
        // (the power source can read Unknown; v0.4.0 ignored the click in
        // exactly that case). Only enabling needs an explicit setting.
        guard on || settings.targetFor(powerSource: source) != nil else {
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
        // Reflect what the machine actually does now, not what was asked.
        statusBar.refresh(active: controller.isSleepSuppressed())
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
