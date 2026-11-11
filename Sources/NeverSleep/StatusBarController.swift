import AppKit
import Sparkle
import NeverSleepCore

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        let menu = NSMenu()
        // Items manage their own enabled state explicitly (isEnabled below).
        // With the default autoenablesItems=true AppKit re-enables items that
        // have a target but no validateMenuItem implementation — which made
        // the read-only mode's "disabled" toggle clickable (v0.4.0 bug).
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
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
            ? "NeverSleep: awake with lid closed (\(powerSource.rawValue))"
            : "NeverSleep: normal sleep"
    }

    private func rebuildMenu() {
        let menu = statusItem.menu ?? NSMenu()
        menu.removeAllItems()
        // About first — the conventional position in a macOS menu.
        let about = NSMenuItem(title: "About NeverSleep", action: #selector(openAbout(_:)), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let effective = active || externallySuppressed
        // In external mode the toggle is genuinely disabled (autoenablesItems
        // is off, so isEnabled is honored) and named for what is actually
        // going on — a "Restore normal sleep" button that does nothing is
        // exactly how v0.4.0 got stuck-looking.
        let toggleTitle = externallySuppressed
            ? "Sleep suppressed outside NeverSleep"
            : (effective ? "Restore normal sleep" : "Keep awake with lid closed")
        let item = NSMenuItem(title: toggleTitle, action: #selector(didToggle(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = !externallySuppressed
        menu.addItem(item)
        menu.addItem(.separator())
        let power = NSMenuItem(title: "Power source: \(powerSource.rawValue)", action: nil, keyEquivalent: "")
        power.isEnabled = false
        menu.addItem(power)
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
        let quit = NSMenuItem(title: "Quit NeverSleep", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
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
    @objc private func quitApp(_ sender: NSMenuItem) { onQuit() }
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
