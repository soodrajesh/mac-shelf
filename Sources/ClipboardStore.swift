import AppKit
import Combine

/// Persists clipboard history to `~/Library/Application Support/ClipKeep/`.
/// Metadata lives in `history.json`; image content is saved alongside as PNG
/// files so the JSON stays small and nothing is base64-inflated.
///
/// `ObservableObject` + `@Published items` (added for MacShelf, unchanged
/// from ClipKeep otherwise) so the SwiftUI Clipboard tab updates live —
/// AppKit callers (the ⌘⇧V picker, the right-click menu) are unaffected,
/// they just read `.items` as before.
final class ClipboardStore: ObservableObject {
    static let maxItems = 40

    private let imagesDir: URL
    private let indexFile: URL

    @Published private(set) var items: [ClipboardItem] = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("ClipKeep", isDirectory: true)
        imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        indexFile = dir.appendingPathComponent("history.json")
        // Clipboard history is the most sensitive thing this app keeps —
        // whatever you copied, verbatim. macOS's default 0755/0644 leaves it
        // readable by every other local account on the Mac; 0700/0600 keeps
        // it to this user. Applied on every launch, not just first create,
        // so histories written by older builds get tightened too.
        try? FileManager.default.createDirectory(
            at: imagesDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        Self.restrictPermissions(of: dir, to: 0o700)
        Self.restrictPermissions(of: imagesDir, to: 0o700)
        load()
        Self.restrictPermissions(of: indexFile, to: 0o600)
    }

    /// Best-effort `chmod`. Silent on failure: a history file that can't be
    /// locked down is still a working history file, and refusing to run
    /// would be a worse outcome than the permissions being loose.
    static func restrictPermissions(of url: URL, to mode: Int) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    func imageURL(for filename: String) -> URL {
        imagesDir.appendingPathComponent(filename)
    }

    /// Inserts new text at the front. Skips if it exactly matches the current
    /// top item — otherwise every poll tick after a picker selection (which
    /// writes that same text back to the pasteboard) would re-add it.
    func addText(_ text: String) {
        if let top = items.first, top.kind == .text, top.text == text { return }
        items.insert(ClipboardItem(id: UUID(), kind: .text, timestamp: Date(), text: text, imageFile: nil), at: 0)
        trim()
        save()
    }

    func addImage(_ image: NSImage) {
        guard let png = Self.pngData(for: image) else { return }
        if let top = items.first, top.kind == .image, let f = top.imageFile,
           let existing = try? Data(contentsOf: imagesDir.appendingPathComponent(f)),
           existing == png {
            return
        }
        let filename = "\(UUID().uuidString).png"
        let imageFile = imagesDir.appendingPathComponent(filename)
        try? png.write(to: imageFile)
        // Copied images are as sensitive as copied text — a screenshot of a
        // password reset email is a clipboard item like any other.
        Self.restrictPermissions(of: imageFile, to: 0o600)
        items.insert(ClipboardItem(id: UUID(), kind: .image, timestamp: Date(), text: nil, imageFile: filename), at: 0)
        trim()
        save()
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            guard let f = item.imageFile, let img = NSImage(contentsOf: imageURL(for: f)) else { return }
            pb.writeObjects([img])
        }
    }

    func clear() {
        items.removeAll()
        try? FileManager.default.removeItem(at: imagesDir)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        save()
    }

    func remove(_ item: ClipboardItem) {
        if item.kind == .image, let f = item.imageFile {
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(f))
        }
        items.removeAll { $0.id == item.id }
        save()
    }

    private func trim() {
        guard items.count > Self.maxItems else { return }
        for stale in items[Self.maxItems...] where stale.kind == .image {
            if let f = stale.imageFile {
                try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(f))
            }
        }
        items = Array(items[..<Self.maxItems])
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFile),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexFile, options: .atomic)
        // An atomic write replaces the file, so the mode has to be re-applied
        // every time rather than set once at creation.
        Self.restrictPermissions(of: indexFile, to: 0o600)
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
