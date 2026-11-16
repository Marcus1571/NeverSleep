import AppKit
import KeyboardShortcuts
import NeverSleepCore

extension KeyboardShortcuts.Name {
    /// The global toggle: activate/deactivate lid-closed sleep suppression
    /// from anywhere (the Preferences recorder field stores the combo).
    static let toggleSuppression = Self("toggleSuppression")
}

/// Curated conflict warnings for the shortcut recorder (0.12.0). Honest
/// scope: macOS has no public API to enumerate other apps' registered global
/// hotkeys, and registration does not fail when two apps share a combo (both
/// receive it) — so a guaranteed "this combo is not free" warning is
/// impossible. This covers the dangerous picks: system-level combos and
/// plain ⌘-letter combos that would shadow the frontmost app's shortcuts
/// (a global hotkey consumes the keypress before apps see it).
enum ShortcutConflicts {
    static func warning(for shortcut: KeyboardShortcuts.Shortcut?) -> String? {
        guard let shortcut, let key = shortcut.key else { return nil }
        let m = shortcut.modifiers
        let cmd = m.contains(.command), shift = m.contains(.shift)
        let label: String
        switch key {
        case .space:
            label = m.contains(.control)
                ? "⌃Space switches the input source — expect a clash."
                : "⌘Space is Spotlight — expect a clash."
        case .escape:
            label = (cmd && m.contains(.option)) ? "⌘⌥Esc is Force Quit — expect a clash." : ""
        case .three, .four, .five:
            label = (cmd && shift) ? "⌘⇧3/4/5 are the screenshot shortcuts — expect a clash." : ""
        default:
            if cmd, !shift, !m.contains(.option), !m.contains(.control),
               (65...90).contains(key.rawValue) {
                let letter = Character(UnicodeScalar(UInt8(key.rawValue)))
                label = "⌘\(letter) shadows the frontmost app's own ⌘\(letter) shortcut in every app — the pressed key never reaches them. Pick a combo with an extra modifier (⌥ or ⌃)."
            } else {
                label = ""
            }
        }
        return label.isEmpty ? nil : label
    }
}
