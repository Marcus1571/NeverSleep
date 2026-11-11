import SwiftUI

/// The About mini page (menu: "About NeverSleep" — first item, macOS
/// convention). Shows the operator's public identity, the app icon, the
/// version, both licenses (MIT for code, GPL-2.0 for the derived art — kept
/// separate per the art provenance rules in AGENTS.md) and the GitHub repo.
struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityLabel("NeverSleep app icon")
            Text("NeverSleep")
                .font(.title2).fontWeight(.bold)
            Text("Version \(version) (build \(build))")
                .font(.caption).foregroundColor(.secondary)
            Divider()
            Text("© 2026 Marcus1571").font(.subheadline)
            Text("MIT (code) · GPL-2.0 (derived menu-bar art)")
                .font(.caption).foregroundColor(.secondary)
            Link("github.com/Marcus1571/NeverSleep",
                 destination: URL(string: "https://github.com/Marcus1571/NeverSleep")!)
                .font(.subheadline)
            Text("Successor to NoSleep — keeps the Mac awake with the lid closed.")
                .font(.footnote).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 300)
    }
}
