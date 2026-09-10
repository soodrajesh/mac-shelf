import Cocoa
import SwiftUI
import Carbon.HIToolbox

// MARK: - App delegate
//
// One NSStatusItem showing mac-monitor's live two-line CPU/MEM readout.
// Left-click toggles an NSPopover (Stats/Calendar/Calculator/Clipboard/Notepad,
// from quick-tools). Right-click shows Free Up Memory / Accessibility /
// Quit. The ⌘⇧V paste-picker and ⌘⇧N notepad opener run via global hotkeys.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var globalClickMonitor: Any?
    private var timer: Timer?
    private var frontmostBeforeShow: NSRunningApplication?

    private let stats = StatsController()
    private let clipboardStore = ClipboardStore()
    private let notepadStore = NotepadStore()
    private let panelState = PanelState()
    private let licenseState = LicenseState()
    private var settingsWindowController: SettingsWindowController!
    private var clipboardMonitor: ClipboardMonitor!
    private var picker: PickerController!
    private var hotKey: HotKey?
    private var notepadHotKey: HotKey?
    /// Populated when `HotKey.init?` returns `nil` (registration failed,
    /// e.g. another app already claims that key combo) — surfaced in the
    /// right-click menu so the failure is visible instead of silent
    /// (UX-AUDIT.md finding F-1). Full remapping UI is out of scope; this is
    /// the minimum "make failure visible" fix.
    private var hotKeyWarnings: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ApplicationMenus.installStandardEditMenu()

        settingsWindowController = SettingsWindowController(licenseState: licenseState)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Re-render when the menu bar switches between light/dark.
        statusItem.button?.addObserver(self, forKeyPath: "effectiveAppearance", options: [.new], context: nil)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 240)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let hosting = NSHostingController(rootView: QuickToolsPanel(
            stats: stats,
            clipboardStore: clipboardStore,
            notepadStore: notepadStore,
            panelState: panelState,
            licenseState: licenseState,
            onSelectClipboardItem: { [weak self] item in self?.selectClipboardItem(item) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        ))
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hosting

        clipboardMonitor = ClipboardMonitor(store: clipboardStore)
        clipboardMonitor.start()
        picker = PickerController(store: clipboardStore)

        // kVK_ANSI_V = 9; cmdKey|shiftKey are Carbon modifier masks for ⌘⇧.
        // Both hotkeys are Pro features (see DESIGN-SYSTEM.md's license
        // pattern / the free-vs-Pro split): registered unconditionally so
        // the shortcut doesn't collide with anything else system-wide, but
        // the action itself checks `licenseState.isProLicensed` at fire
        // time and opens Settings' License tab instead when unlicensed.
        hotKey = HotKey(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.handlePastePickerHotkey()
        }
        if hotKey == nil {
            let message = "Global shortcut ⌘⇧V could not be registered — it may be in use by another app."
            NSLog("MacShelf: \(message)")
            hotKeyWarnings.append(message)
        }

        // kVK_ANSI_N = 45 — open popover on Notepad tab.
        notepadHotKey = HotKey(keyCode: 45, modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.handleNotepadHotkey()
        }
        if notepadHotKey == nil {
            let message = "Global shortcut ⌘⇧N could not be registered — it may be in use by another app."
            NSLog("MacShelf: \(message)")
            hotKeyWarnings.append(message)
        }

        if !PasteSimulator.isTrusted {
            PasteSimulator.requestAccessibility()
        }

        stats.refresh(includeDetails: false)
        refreshStatusItem()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStatsAndMenuBar()
        }

        Task { await licenseState.refresh() }
    }

    private func handlePastePickerHotkey() {
        guard licenseState.isProLicensed else {
            openSettings()
            return
        }
        picker.show()
    }

    private func handleNotepadHotkey() {
        guard licenseState.isProLicensed else {
            openSettings()
            return
        }
        showNotepadFromHotkey()
    }

    private func openSettings() {
        closePopover()
        settingsWindowController.show()
    }

    private func refreshStatsAndMenuBar() {
        let details = popover.isShown && panelState.selectedTab == 0
        stats.refresh(includeDetails: details)
        refreshStatusItem()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "effectiveAppearance" else { return }
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        let isDark = statusItem.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
        statusItem.button?.image = makeStatusImage(
            cpuValue: stats.cpuText, cpuHigh: stats.cpuHigh,
            memValue: stats.memText, memHigh: stats.memHigh,
            isDark: isDark)
    }

    @objc func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            openPopover(relativeTo: button)
        }
    }

    private func showNotepadFromHotkey() {
        panelState.openNotepadTab()
        guard let button = statusItem.button else { return }
        if popover.isShown {
            return
        }
        openPopover(relativeTo: button)
    }

    private func openPopover(relativeTo button: NSStatusBarButton) {
        frontmostBeforeShow = NSWorkspace.shared.frontmostApplication
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        configurePopoverWindow()
        startGlobalClickMonitor()
        stats.refresh(includeDetails: panelState.selectedTab == 0)
    }

    /// `.transient` alone doesn't reliably close the popover when a click
    /// lands on a *different* app's status item — a global mouse-down
    /// monitor is the reliable fix (only fires for clicks outside our own
    /// app, so it can't interfere with our own button's toggle logic).
    private func configurePopoverWindow() {
        guard let window = popover.contentViewController?.view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.makeKey()
    }

    private func startGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    private func selectClipboardItem(_ item: ClipboardItem) {
        closePopover()
        clipboardStore.copyToPasteboard(item)
        PasteSimulator.pasteInto(frontmostBeforeShow)
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let freeMemItem = NSMenuItem(title: "Free Up Memory", action: #selector(freeMemoryAction), keyEquivalent: "")
        freeMemItem.target = self
        menu.addItem(freeMemItem)

        if !PasteSimulator.isTrusted {
            let permItem = NSMenuItem(title: "Enable Accessibility for Auto-Paste…",
                                       action: #selector(requestAccessibility), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }

        if !hotKeyWarnings.isEmpty {
            menu.addItem(.separator())
            for warning in hotKeyWarnings {
                let warningItem = NSMenuItem(title: "⚠️ \(warning)", action: nil, keyEquivalent: "")
                warningItem.isEnabled = false
                menu.addItem(warningItem)
            }
        }

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit MacShelf", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func freeMemoryAction() {
        stats.freeMemory()
    }

    @objc func requestAccessibility() {
        PasteSimulator.requestAccessibility()
    }

    @objc func openSettingsAction() {
        openSettings()
    }

    @objc func quit() {
        statusItem.button?.removeObserver(self, forKeyPath: "effectiveAppearance")
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        configurePopoverWindow()
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
