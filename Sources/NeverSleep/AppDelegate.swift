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
    private var aboutWindow: NSWindow?
    private var menuUpdater: AnyCancellable?
    private var lastKnownPowerSource: PowerSource = .unknown
    private var lastKnownActive = false
    private var lastKnownLidClosed: Bool? = nil
    private var externallySuppressed = false
    private var blankedThisClosure = false
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
                                        onOpenAbout: { [weak self] in self?.openAbout() },
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
        // 1 s poll — display wake on lid open must feel instant; pmset spawns
        // and IORegistry reads this fast are negligible. Richer IOKit
        // notifications remain a possible refinement (see STATUS open item).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
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
        // Lid-close display handling (v0.5.0): with suppression active and
        // no external display attached, a closed lid blanks the panel via
        // the display-sleep path (apps/audio/network untouched). Not gated
        // on the lid transition alone: this also covers enabling suppression
        // while the lid is already closed, and unplugging the external
        // screen mid-closure. An attached external display = clamshell
        // working mode — displays are never touched. Unknown lid → never
        // blank (desktops, unreadable registry).
        let lidClosed = LidState.isClosed()
        if lidClosed != lastKnownLidClosed {
            Log.info("lid: \(lidClosed.map { $0 ? "closed" : "open" } ?? "unknown") (was \(lastKnownLidClosed.map { $0 ? "closed" : "open" } ?? "unknown"))")
            lastKnownLidClosed = lidClosed
        }
        if liveActive, lidClosed == true, !blankedThisClosure,
           !DisplayControl.externalDisplayAttached() {
            blankedThisClosure = true
            DisplayControl.sleepNow()
        }
        if lidClosed == false, blankedThisClosure {
            blankedThisClosure = false
            DisplayControl.wake()
        }
        guard source != lastKnownPowerSource || liveActive != lastKnownActive || initial else { return }
        let sourceChanged = source != lastKnownPowerSource
        Log.info("state: power=\(source.rawValue) suppressed=\(liveActive) (was power=\(lastKnownPowerSource.rawValue) suppressed=\(lastKnownActive))")
        lastKnownPowerSource = source
        lastKnownActive = liveActive
        statusBar.update(powerSource: source, active: liveActive)
        if sourceChanged {
            // NoSleep parity (KB feature 10): the per-source preference governs
            // continuously — a saved "never sleep on AC" is re-applied whenever
            // the machine lands on AC, not only at launch. This is the fix for
            // the 2026-11-14 morning report: a clean shutdown restores normal
            // sleep by design, and nothing ever re-armed the saved preference.
            enforcePreference()
        }
    }

    /// Drives the live pmset state toward the saved per-source preference for
    /// the current power source (NoSleep semantics: the checkbox IS the
    /// control; the menu toggle keeps it in sync). Never runs on an
    /// externally suppressed machine (read-only gate — that config is not
    /// ours to touch). One-directional no-op when state already matches.
    private func enforcePreference() {
        guard !externallySuppressed else { return }
        let source = lastKnownPowerSource
        guard let target = settings.targetFor(powerSource: source),
              controller.isSleepSuppressed() != target else { return }
        Log.info("preference enforcement: applying saved \(source.rawValue) preference on=\(target)")
        let outcome = controller.setSleepSuppressed(target)
        Log.info("preference enforcement result: \(outcome.userMessage)")
        if case .failed(let reason) = outcome {
            Log.error("preference enforcement failed: \(reason)")   // log only — no alert on an automatic action
        }
        statusBar.refresh(active: controller.isSleepSuppressed())
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
        // NoSleep semantics: the menu toggle IS the per-source control (the
        // Preferences checkbox mirrors it). Keeping the saved preference in
        // sync is what makes launch re-arm and power-source enforcement agree
        // with what the user actually did — without this, the 2026-11-14
        // morning report happens: suppression on at shutdown, gone at relaunch.
        settings.setTarget(on: on, powerSource: source)
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

    /// The About mini page: app icon, version, the operator's public
    /// identity, both licenses and the repo link (see AboutView). Reused
    /// single window, same pattern as openPreferences.
    private func openAbout() {
        if aboutWindow == nil {
            let hosting = NSHostingController(rootView: AboutView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "About NeverSleep"
            window.styleMask = [.titled, .closable]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.setContentSize(hosting.view.fittingSize)
            window.center()
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        aboutWindow?.makeFirstResponder(nil)   // don't leave the repo link focus-ringed on open
        NSApp.activate(ignoringOtherApps: true)
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
