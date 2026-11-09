import SwiftUI
import NeverSleepCore

struct PreferencesView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NeverSleep keeps the Mac awake with the lid closed — ex-builtin NoSleep behavior.").font(.headline)
            Toggle("Never sleep on AC Adapter", isOn: $settings.suppressOnAC)
            Toggle("Never sleep on Battery", isOn: $settings.suppressOnBattery)
            Divider()
            Toggle("Require password on display opening", isOn: $settings.lockScreenOnLidClose)
            Toggle("Use black and white menu bar icons", isOn: $settings.useBlackWhiteIcons)
            Divider()
            Text("A Mac awake with a closed lid has reduced cooling — use it while you are using the machine, not in a backpack.").font(.footnote).foregroundColor(.secondary)
        }
        .padding(22)
        .frame(width: 460)
    }
}
