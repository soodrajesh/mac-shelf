import AppKit

/// The ⌘⇧V floating picker: type to filter, ↑/↓ to navigate, Return (or a
/// click) to paste, Esc to dismiss.
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Routes the panel's traffic-light close button through `hide()` instead of
/// the default `close()`, which would deallocate the panel (isReleasedWhenClosed)
/// and crash the next time the hotkey fires.
extension PickerController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}

/// `.nonactivatingPanel` lets this panel become key and take keystrokes
/// without activating ClipKeep's own app — so the previously frontmost app
/// never loses its "active" status, and pasting back into it afterward
/// doesn't require reactivating a background process.
final class PickerController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let store: ClipboardStore
    private let panel: PickerPanel
    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let clearAllButton = NSButton()
    private var filtered: [ClipboardItem] = []
    private var previouslyActiveApp: NSRunningApplication?

    init(store: ClipboardStore) {
        self.store = store
        panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
                             styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .resizable],
                             backing: .buffered, defer: false)
        super.init()
        panel.delegate = self
        configurePanel()
    }

    private func configurePanel() {
        panel.title = "ClipKeep"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 380))
        panel.contentView = content

        searchField.placeholderString = "Search clipboard history…"
        searchField.font = .systemFont(ofSize: 14)
        searchField.delegate = self
        searchField.focusRingType = .none
        searchField.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.rowHeight = 40
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.menu = makeRowContextMenu()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.width = 400
        tableView.addTableColumn(col)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        clearAllButton.title = "Clear All"
        clearAllButton.bezelStyle = .inline
        clearAllButton.isBordered = false
        clearAllButton.font = .systemFont(ofSize: 11)
        clearAllButton.contentTintColor = .systemRed
        clearAllButton.target = self
        clearAllButton.action = #selector(clearAllClicked)
        clearAllButton.toolTip = "Delete all clipboard history"
        clearAllButton.setAccessibilityLabel("Delete all clipboard history")
        clearAllButton.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(searchField)
        content.addSubview(scrollView)
        content.addSubview(clearAllButton)
        let topAnchor = (panel.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.topAnchor
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            clearAllButton.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            clearAllButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: clearAllButton.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    /// Right-click "Delete" on a row — mirrors the popover tab's context
    /// menu affordance (see `ClipboardListView`). `NSMenu`'s validation
    /// callback resolves which row was clicked via `tableView.clickedRow`,
    /// which AppKit sets before showing a view's context menu.
    private func makeRowContextMenu() -> NSMenu {
        let menu = NSMenu()
        let delete = NSMenuItem(title: "Delete", action: #selector(deleteClickedRow), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        return menu
    }

    @objc private func deleteClickedRow() {
        let row = tableView.clickedRow
        guard row >= 0, row < filtered.count else { return }
        let item = filtered[row]
        store.remove(item)
        refilter()
    }

    @objc private func clearAllClicked() {
        guard !store.items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "This removes all \(store.items.count) saved items. This can't be undone."
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        panel.makeKeyAndOrderFront(nil)
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.store.clear()
            self?.refilter()
        }
    }

    func show() {
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
        searchField.stringValue = ""
        refilter()

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2 + 80))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    private func hide() {
        panel.orderOut(nil)
    }

    private func refilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filtered = q.isEmpty ? store.items : store.items.filter { $0.preview.lowercased().contains(q) }
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        refilter()
    }

    /// Arrow/return/escape reach here even though the search field's field
    /// editor has keyboard focus — the standard idiom for a filterable list.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)):
            selectCurrentRow(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide(); return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let next = min(max(tableView.selectedRow + delta, 0), filtered.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func rowClicked() {
        selectCurrentRow()
    }

    private func selectCurrentRow() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        hide()
        store.copyToPasteboard(filtered[row])
        PasteSimulator.pasteInto(previouslyActiveApp)
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < filtered.count else { return PickerRowView.textRowHeight }
        switch filtered[row].kind {
        case .text: return PickerRowView.textRowHeight
        case .image: return PickerRowView.imageRowHeight
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? PickerRowView ?? PickerRowView(identifier: cellID)
        cell.configure(with: filtered[row], store: store)
        return cell
    }
}
