import AppKit
import Combine
import Foundation

/// Scratch pad persisted under `~/Library/Application Support/MacShelf/notepad.txt`.
final class NotepadStore: ObservableObject {
    @Published var text: String {
        didSet { scheduleSave() }
    }

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("MacShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("notepad.txt")
        text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func saveNow() {
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func clear() {
        text = ""
        saveWorkItem?.cancel()
        saveNow()
    }
}
