import SwiftUI
import KeyboardShortcuts
import NeverSleepCore

struct PreferencesView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NeverSleep keeps the Mac awake with the lid closed — ex-builtin NoSleep behavior.").font(.headline)
            Toggle("Never sleep on AC Adapter", isOn: $settings.suppressOnAC)
            Toggle("Never sleep on Battery", isOn: $settings.suppressOnBattery)
            Divider()
            Toggle("Use black and white menu bar icons", isOn: $settings.useBlackWhiteIcons)
            Toggle("Launch NeverSleep at login", isOn: $settings.launchAtLogin)
            Divider()
            // Global keyboard toggle (0.12.0): the recorder is the standard
            // black field (KeyboardShortcuts package) — click it, press the
            // combo; the shortcut works system-wide, like the double-click.
            Text("Keyboard shortcut").font(.subheadline).fontWeight(.semibold)
            // The recorder's own ✕ (embedded search-field cancel cell) does not
            // persist the removal on macOS 27 (operator-reported, 2026-11-16) —
            // so clearing goes through our own button, which calls the
            // package's public removal API (setShortcut(nil): unregister +
            // storage removal + the change notification the recorder observes).
            HStack(spacing: 8) {
                KeyboardShortcuts.Recorder(for: .toggleSuppression)
                Button {
                    KeyboardShortcuts.setShortcut(nil, for: .toggleSuppression)
                } label: {
                    Image(systemName: "delete.left")
                        .frame(width: 30, height: 24)
                }
                .help("Clear the shortcut")
            }
            if let warning = settings.shortcutWarning {
                Text(warning).font(.caption2).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Toggles NeverSleep from anywhere — even when another app is frontmost. macOS allows two apps to claim the same combo; if pressing it also triggers something else, pick another.")
                    .font(.caption2).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Text("A Mac awake with a closed lid has reduced cooling — use it while you are using the machine, not in a backpack.").font(.footnote).foregroundColor(.secondary)
        }
        .padding(22)
        .frame(width: 460)
    }
}
