import AppKit
import SwiftUI

/// MacPerch' Settings pane, opened via the right-click menu's "Settings…"
/// item (this app has no Dock icon / `Settings` Scene to wire ⌘, to
/// automatically — see `main.swift`). Tabbed like mac-cleanup's
/// `SettingsView`: Appearance, Text Size, License, About, in that order per
/// `DESIGN-SYSTEM.md`.
struct SettingsView: View {
    @ObservedObject var licenseState: LicenseState

    var body: some View {
        TabView {
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            LicenseTab(licenseState: licenseState)
                .tabItem { Label("License", systemImage: "checkmark.seal") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 360)
    }
}

private struct AppearanceTab: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("textSize") private var textSize = TextSizeSetting.medium

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .appFont(.headline)
                Picker("", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Text Size")
                    .appFont(.headline)
                Picker("", selection: $textSize) {
                    ForEach(TextSizeSetting.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Spacer()
        }
        .padding(20)
    }
}

private struct LicenseTab: View {
    @ObservedObject var licenseState: LicenseState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LicenseManagementView(licenseState: licenseState)
            Spacer()
        }
        .padding(20)
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

            Text("MacPerch \(version)")
                .appFont(.headline)
            Text("Menu-bar system monitor, quick tools, clipboard history, and notepad.")
                .appFont(.callout)
                .foregroundStyle(.secondary)

            Button("Report a Bug or Request a Feature…") {
                NSWorkspace.shared.open(URL(string: "https://github.com/soodrajesh/mac-tools/issues/new")!)
            }
            .buttonStyle(.link)

            Spacer()
        }
        .padding(20)
    }
}

/// Owns the one Settings `NSWindow` (this app has no `Settings` Scene to
/// let SwiftUI manage the window for it — see `main.swift`). Reused across
/// opens rather than recreated, so window position/size persists across a
/// session the way a real Settings window would.
final class SettingsWindowController {
    private var window: NSWindow?
    private let licenseState: LicenseState

    init(licenseState: LicenseState) {
        self.licenseState = licenseState
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(licenseState: licenseState))
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "MacPerch Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
