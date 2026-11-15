import AppKit
import Sparkle
import NeverSleepCore

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let settings: SettingsStore
    private var onToggle: (Bool) -> Void
    private var onOpenAbout: () -> Void
    private var onOpenPrefs: () -> Void
    private var onQuit: () -> Void
    // Sparkle (bundled runs only): the menu item targets the updater directly.
    private let updater: SPUStandardUpdaterController?
    private var externallySuppressed: Bool = false
    private var active: Bool = false
    private var powerSource: PowerSource = .unknown

    init(settings: SettingsStore,
         onToggle: @escaping (Bool) -> Void,
         onOpenAbout: @escaping () -> Void,
         onOpenPrefs: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         updater: SPUStandardUpdaterController?,
         externallySuppressed: Bool) {
        self.settings = settings
        self.onToggle = onToggle
        self.onOpenAbout = onOpenAbout
        self.onOpenPrefs = onOpenPrefs
        self.onQuit = onQuit
        self.updater = updater
        self.externallySuppressed = externallySuppressed
        super.init()
        // Items manage their own enabled state explicitly (isEnabled below).
        // With the default autoenablesItems=true AppKit re-enables items that
        // have a target but no validateMenuItem implementation — which made
        // the read-only mode's "disabled" toggle clickable (v0.4.0 bug).
        menu.autoenablesItems = false
        menu.delegate = self
        renderIcon(active: false)
        rebuildMenu()   // read-only path never calls update(); menu must still have Quit
    }

    func update(powerSource: PowerSource, active: Bool) {
        self.powerSource = powerSource
        self.active = active
        renderIcon(active: active)
        rebuildMenu()
    }

    func refresh(active: Bool) {
        self.active = active
        renderIcon(active: active)
        rebuildMenu()
    }

    private func renderIcon(active: Bool) {
        // Effective suppression: a leftover adopted at startup (active) and
        // an externally-configured machine (externallySuppressed) both mean
        // the Mac will not sleep — the icon must say so. (v0.4.0 rendered
        // the inactive outline icon while the machine was actually
        // suppressed in external mode.)
        let effective = active || externallySuppressed
        // NoSleep parity #3 (imitating the original app): filled Zz glyph while
        // suppression is active, outline Zz glyph while normal sleep — the exact
        // pair the original swapped on state change (ZzActive/ZzInactive, both
        // template). We ship both derived glyphs as vector PDFs; the SF-Symbol
        // "zzz" stays as the fallback for a bare `swift run` (no bundle).
        let glyph = effective ? "menubar-z-active" : "menubar-z-inactive"
        var img: NSImage
        if let url = Bundle.main.url(forResource: glyph, withExtension: "pdf"),
           let bundled = NSImage(contentsOf: url) {
            img = bundled
        } else {
            img = NSImage(systemSymbolName: "zzz", accessibilityDescription: "NeverSleep") ?? NSImage()
        }
        if settings.useBlackWhiteIcons {
            // Template rendering gives the B/W menu-bar behavior on light+dark
            // for free (alpha decides the shape; menu-tint does the coloring).
            img.isTemplate = true
        } else if effective {
            let tinted: NSImage = img.tinted(with: NSColor(red: 0.31, green: 0.79, blue: 0.91, alpha: 1.0))
            img = tinted
        } else {
            let tinted: NSImage = img.tinted(with: .lightGray)
            img = tinted
        }
        statusItem.button?.image = img
        statusItem.button?.toolTip = effective
            ? "NeverSleep: awake with lid closed (\(powerSource.rawValue)) — double-click to toggle · right-click for menu"
            : "NeverSleep: normal sleep — double-click to keep awake · right-click for menu"
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        // The menu is ALWAYS detached (since 0.10.0): the icon's gestures are
        // double-click = toggle and right-click/⌃-click = open this menu. A
        // detached menu is required — with it attached, a double-click's first
        // press would open the menu instead of starting the pair.
        statusItem.menu = nil
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let effective = active || externallySuppressed

        // Status header — the state in plain words, color-coded. Not clickable
        // (isEnabled = false, honored because autoenablesItems is off).
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        let headerText: NSAttributedString
        let subText: String
        if externallySuppressed {
            headerText = joined(dot("●", color: .systemOrange), bold("Sleep suppressed outside NeverSleep", color: .systemOrange))
            subText = "pmset is managed outside this app"
        } else if effective {
            headerText = joined(dot("●", color: .systemGreen), bold("Keeping the Mac awake", color: .systemGreen))
            subText = "lid closed = no sleep · display off"
        } else {
            headerText = joined(dot("○", color: .secondaryLabelColor), bold("Normal macOS sleep", color: .secondaryLabelColor))
            subText = "Mac sleeps normally when lid closes"
        }
        header.attributedTitle = headerText
        menu.addItem(header)
        let sub = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        sub.isEnabled = false
        sub.attributedTitle = small(subText)
        menu.addItem(sub)
        menu.addItem(.separator())

        // THE toggle — the loudest item in the menu, titled as the action, with
        // a hint suffix. In external mode it is genuinely disabled (see the
        // v0.4.0 lesson in the header comment) and named for what is going on.
        let toggle = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = !externallySuppressed
        toggle.action = externallySuppressed ? nil : #selector(didToggle(_:))
        if externallySuppressed {
            toggle.attributedTitle = bold("Sleep suppressed outside NeverSleep", color: .secondaryLabelColor)
        } else if effective {
            toggle.attributedTitle = joined(bold("Restore normal sleep", color: .labelColor), small("  click to turn OFF"))
        } else {
            toggle.attributedTitle = joined(bold("Keep awake when lid closes", color: .labelColor), small("  click to turn ON"))
        }
        menu.addItem(toggle)
        menu.addItem(.separator())

        let power = NSMenuItem(title: "Power source: \(powerSource.rawValue)", action: nil, keyEquivalent: "")
        power.isEnabled = false
        menu.addItem(power)
        // About demoted from the macOS-conventional first slot deliberately:
        // the top of the menu belongs to the state + the one function this app
        // has (the whole point of the 2026-11-15 redesign). About, Preferences
        // and Quit live in the lower cluster.
        let about = NSMenuItem(title: "About NeverSleep", action: #selector(openAbout(_:)), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        if let updater {
            // Sparkle's standard target/action; enabled state handled by Sparkle itself.
            let checkUpdates = NSMenuItem(title: "Check for Updates…",
                                          action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                          keyEquivalent: "u")
            checkUpdates.target = updater
            menu.addItem(checkUpdates)
        }
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        // Live truth each rebuild, so an external change in System Settings matches too.
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.state = LoginItem.isEnabled() ? .on : .off
        login.target = self
        menu.addItem(login)
        menu.addItem(.separator())
        // Report a Bug: SF Symbol ladybug (template — macOS tints it with the
        // row color), opens the repo's Issues page. Same placement as
        // diskled-plus: last before Quit.
        let bug = NSMenuItem(title: "Report a Bug…",
                             action: #selector(reportBug(_:)),
                             keyEquivalent: "")
        bug.target = self
        bug.image = NSImage(systemSymbolName: "ladybug.fill", accessibilityDescription: "Report a Bug")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        menu.addItem(bug)
        let quit = NSMenuItem(title: "Quit NeverSleep", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Click handling — double-click toggles (timing-based detection:
    /// NSEvent.clickCount is unreliable here, both mouseUps of a pair can
    /// report cc=1), left single click intentionally does nothing, right-click
    /// (or ⌃-click) opens the menu so Preferences/Quit stay reachable.
    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        // Double-click detection is timing-based (two actions within the
        // system double-click interval): NSEvent.clickCount is unreliable
        // here — posted events and some status-item paths deliver cc=1 on
        // both clicks of a pair.
        let now = Date()
        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            lastIconClick = nil   // a menu open breaks a click pair
            openMenuFromButton()
            return
        }
        guard event.type == .leftMouseUp else { return }
        let isDouble = lastIconClick.map { now.timeIntervalSince($0) < NSEvent.doubleClickInterval } ?? false
        if isDouble {
            lastIconClick = nil
            onToggle(!active)
        } else {
            lastIconClick = now   // single click: no-op by design, timestamp remembered for the pair
        }
    }

    private var lastIconClick: Date?

    /// Programmatic menu open for the right-click path (the menu is detached
    /// in double-click mode, so AppKit's auto-open is unavailable).
    private func openMenuFromButton() {
        statusItem.popUpMenu(menu)
    }

    @objc private func didToggle(_ sender: NSMenuItem) {
        onToggle(!active)
    }
    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let on = !(sender.state == .on)
        settings.launchAtLogin = on   // routes through SettingsStore: service call + persisted default
        sender.state = on ? .on : .off
        if LoginItem.isEnabled() != on {
            let alert = NSAlert()
            alert.messageText = "NeverSleep"
            alert.informativeText = "Could not \(on ? "register" : "unregister") the login item — see the NeverSleep log."
            alert.runModal()
        }
    }
    @objc private func openAbout(_ sender: NSMenuItem) { onOpenAbout() }
    @objc private func openPreferences(_ sender: NSMenuItem) { onOpenPrefs() }
    /// Opens the repository's GitHub Issues page in the default browser.
    @objc private func reportBug(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://github.com/Marcus1571/NeverSleep/issues")!)
    }
    @objc private func quitApp(_ sender: NSMenuItem) { onQuit() }
}

// Attributed-string builders for the redesigned menu (state header + the
// loud toggle). Native AppKit only — bold/colored text is what makes the
// one function of this app unmistakable in the menu (2026-11-15 redesign).
private func joined(_ parts: NSAttributedString...) -> NSAttributedString {
    let out = NSMutableAttributedString()
    parts.forEach { out.append($0) }
    return out
}

private func bold(_ text: String, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.boldSystemFont(ofSize: 13),
        .foregroundColor: color,
    ])
}

private func small(_ text: String) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.secondaryLabelColor,
    ])
}

private func dot(_ glyph: String, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: glyph + "  ", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: color,
    ])
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            color.set()
            self.draw(in: rect, from: NSRect(origin: .zero, size: self.size), operation: .sourceOver, fraction: 1.0)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return img
    }
}
