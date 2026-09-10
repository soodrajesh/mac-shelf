import SwiftUI

/// Single popover content: icon-only segmented switcher (Stats / Calendar /
/// Calculator / Clipboard / Notepad). Tabs stay mounted (hidden) so switching
/// does not recreate heavy views like the notepad `NSTextView`.
struct QuickToolsPanel: View {
    let stats: StatsController
    let clipboardStore: ClipboardStore
    let notepadStore: NotepadStore
    @ObservedObject var panelState: PanelState
    let onSelectClipboardItem: (ClipboardItem) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $panelState.selectedTab) {
                Image(systemName: "cpu").tag(0)
                Image(systemName: "calendar").tag(1)
                Image(systemName: "plus.slash.minus").tag(2)
                Image(systemName: "doc.on.clipboard").tag(3)
                Image(systemName: "note.text").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ZStack {
                tab(0) { StatsView(stats: stats) }
                tab(1) { CalendarView() }
                tab(2) { CalculatorView() }
                tab(3) { ClipboardListView(store: clipboardStore, onSelect: onSelectClipboardItem) }
                tab(4) { NotepadView(store: notepadStore) }
            }
            .modifier(SelectedTabChangeHandler(selectedTab: panelState.selectedTab, onChange: handleTabChange))
        }
        .padding(10)
        .frame(width: 280, height: 240)
        .background(PopoverVisualEffect())
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
            .frame(width: 260, height: 190)
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
