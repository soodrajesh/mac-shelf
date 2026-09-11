import AppKit
import SwiftUI

/// MacShelf' Settings pane, opened via the right-click menu's "Settings…"
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
            CalendarTab()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            LicenseTab(licenseState: licenseState)
                .tabItem { Label("License", systemImage: "checkmark.seal") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 380)
    }
}

private struct AppearanceTab: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("textSize") private var textSize = TextSizeSetting.medium

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    IconTile(systemName: "paintbrush.fill", tileSize: 22)
                    Text("Appearance")
                        .appFont(.headline, weight: .bold)
                }
                Picker("", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .tint(Color.appAccent)
            }
            .cardStyle(padding: 14)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    IconTile(systemName: "textformat.size", tileSize: 22)
                    Text("Text Size")
                        .appFont(.headline, weight: .bold)
                }
                Picker("", selection: $textSize) {
                    ForEach(TextSizeSetting.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .tint(Color.appAccent)
            }
            .cardStyle(padding: 14)

            Spacer()
        }
        .padding(20)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appearanceMode)
    }
}

private struct CalendarTab: View {
    @AppStorage("holidayCountryCode") private var holidayCountryCode: String = HolidayCountry.defaultCountryCode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    IconTile(systemName: "calendar.badge.clock", tileSize: 22)
                    Text("Public Holidays")
                        .appFont(.headline, weight: .bold)
                }
                Text("Pick a country to highlight its public holidays on the calendar with a small orange dot.")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)

                Picker("Country", selection: $holidayCountryCode) {
                    Text("None").tag("")
                    Divider()
                    ForEach(HolidayCountry.supportedCountries) { country in
                        Text(country.name).tag(country.code)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.appAccent)
            }
            .cardStyle(padding: 14)

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
        VStack(alignment: .leading, spacing: 12) {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconTile(systemName: "shippingbox.fill", tileSize: 22)
                    Text("MacShelf \(version)")
                        .appFont(.headline, weight: .bold)
                }
                Text("Menu-bar system monitor, quick tools, clipboard history, and notepad.")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)

                Button("Report a Bug or Request a Feature…") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/soodrajesh/mac-tools/issues/new")!)
                }
                .buttonStyle(.link)
                .tint(Color.appAccent)
            }
            .cardStyle(padding: 14)

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
        newWindow.title = "MacShelf Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
