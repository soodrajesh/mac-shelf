import SwiftUI

/// Single popover content: icon-only segmented switcher (Stats / Calendar /
/// Calculator / Clipboard / Notepad). Tabs stay mounted (hidden) so switching
/// does not recreate heavy views like the notepad `NSTextView`.
struct QuickToolsPanel: View {
    let stats: StatsController
    let clipboardStore: ClipboardStore
    let notepadStore: NotepadStore
    @ObservedObject var panelState: PanelState
    @ObservedObject var licenseState: LicenseState
    let onSelectClipboardItem: (ClipboardItem) -> Void
    let onOpenSettings: () -> Void

    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("textSize") private var textSize = TextSizeSetting.medium

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $panelState.selectedTab) {
                Image(systemName: "cpu").tag(0)
                    .accessibilityLabel("Stats")
                Image(systemName: "calendar").tag(1)
                    .accessibilityLabel("Calendar")
                Image(systemName: "plus.slash.minus").tag(2)
                    .accessibilityLabel("Calculator")
                Image(systemName: "doc.on.clipboard").tag(3)
                    .accessibilityLabel("Clipboard")
                Image(systemName: "note.text").tag(4)
                    .accessibilityLabel("Notepad")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(Color.appAccent)
            .help("Switch tool")

            ZStack {
                tab(0) { StatsView(stats: stats) }
                tab(1) { CalendarView() }
                tab(2) { CalculatorView() }
                tab(3) { clipboardTab }
                tab(4) { notepadTab }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: panelState.selectedTab)
            .modifier(SelectedTabChangeHandler(selectedTab: panelState.selectedTab, onChange: handleTabChange))
        }
        .padding(10)
        .frame(width: 300, height: 280)
        .background(PopoverVisualEffect(appearanceOverride: appearanceMode.nsAppearanceName))
        .environment(\.textScale, textSize.scaleFactor)
        .preferredColorScheme(appearanceMode.colorScheme)
    }

    /// Clipboard history is a Pro feature — see `DESIGN-SYSTEM.md` §License
    /// and the task's free/Pro split. Free tier is Stats/Calendar/Calculator.
    @ViewBuilder
    private var clipboardTab: some View {
        if licenseState.isProLicensed {
            ClipboardListView(store: clipboardStore, onSelect: onSelectClipboardItem)
        } else {
            UnlockProView(feature: "Clipboard history", systemImage: "doc.on.clipboard", onUnlock: onOpenSettings)
        }
    }

    @ViewBuilder
    private var notepadTab: some View {
        if licenseState.isProLicensed {
            NotepadView(store: notepadStore)
        } else {
            UnlockProView(feature: "The Notepad", systemImage: "note.text", onUnlock: onOpenSettings)
        }
    }

    private func handleTabChange(_ tab: Int) {
        if tab == 0 {
            stats.refresh(includeDetails: true)
        }
    }

    @ViewBuilder
    private func tab(_ index: Int, @ViewBuilder content: () -> some View) -> some View {
        let visible = panelState.selectedTab == index
        content()
            .frame(width: 280, height: 220)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

/// Deployment target is macOS 13, but the two-parameter `onChange(of:)` is
/// 14.0+. Branch on availability so 14+ gets the non-deprecated API while
/// 13 still builds and runs against the old one.
private struct SelectedTabChangeHandler: ViewModifier {
    let selectedTab: Int
    let onChange: (Int) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onChange(of: selectedTab) { _, newValue in onChange(newValue) }
        } else {
            content.onChange(of: selectedTab) { newValue in onChange(newValue) }
        }
    }
}
