import AppKit
import SwiftUI
import NeverSleepCore

/// The one-time heat-warning panel (0.14.0) — replaces the 0.13.0 NSAlert with
/// the operator-approved card design: Zz header, three illustrated cards
/// (No enclosed spaces / Airflow matters / Heat & performance), a "Don't show
/// again" checkbox and Cancel / Keep awake buttons. Shown modally before the
/// first activation; the wording is research-backed (findings.md §16 — never
/// the false "this could break your Mac" claim).
enum HeatWarningPanel {
    struct Result {
        let proceed: Bool
        let dontShowAgain: Bool
    }

    static func run() -> Result {
        var proceed = false
        var dontShowAgain = false

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
                              styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.title = "NeverSleep"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        // Frameless card look: the traffic lights would sit on the header art.
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        window.contentView = NSHostingView(rootView: HeatWarningView(
            onKeep: { dontShow in
                proceed = true
                dontShowAgain = dontShow
                NSApp.stopModal()
            },
            onCancel: {
                NSApp.stopModal()
            }))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return Result(proceed: proceed, dontShowAgain: dontShowAgain)
    }
}

private struct HeatWarningView: View {
    let onKeep: (Bool) -> Void
    let onCancel: () -> Void
    @State private var dontShowAgain = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keeping the Mac awake with the lid closed")
                        .font(.title2).fontWeight(.bold)
                    Text("The Mac can stay awake even with the lid closed, but placement and heat matter.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 14) {
                card(main: "bag.fill", badge: "exclamationmark.triangle.fill", secondary: nil,
                     tint: .orange,
                     title: "No enclosed spaces",
                     body: "Never in a bag or other enclosed space while it stays awake — that's the one real hazard.")
                card(main: "laptopcomputer", badge: "wind", secondary: nil,
                     tint: .blue,
                     title: "Airflow matters",
                     body: "Use a hard, flat surface to keep airflow open — never bedding, pillows, or your lap for long.")
                card(main: "laptopcomputer", badge: "fan", secondary: "battery.100",
                     tint: .blue,
                     title: "Heat & performance",
                     body: "Heavy work runs hotter closed: expect fans and slower speed, and more battery wear over time.")
            }
            Divider()
            HStack {
                Toggle("Don't show again", isOn: $dontShowAgain)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Keep awake") { onKeep(dontShowAgain) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 700)
    }

    /// One card: the illustration zone (big symbol + small badge symbols on a
    /// soft background), then the badge + bold title and the body text.
    private func card(main: String, badge: String, secondary: String?,
                      tint: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
                Image(systemName: main)
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    if let secondary {
                        Image(systemName: secondary)
                            .font(.system(size: 22))
                            .foregroundColor(tint)
                    }
                    Image(systemName: badge)
                        .font(.system(size: 22))
                        .foregroundColor(tint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(8)
            }
            .frame(height: 120)
            HStack(spacing: 8) {
                Image(systemName: badge)
                    .foregroundColor(tint)
                Text(title).font(.headline)
            }
            Text(body).font(.footnote).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }
}
