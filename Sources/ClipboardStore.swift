import AppKit
import Combine

/// Persists clipboard history to `~/Library/Application Support/MacShelf/Clipboard/`.
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
        let dir = support.appendingPathComponent("MacShelf", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
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

        Self.migrateFromClipKeepIfNeeded(
            support: support, newDir: dir, newImagesDir: imagesDir, newIndexFile: indexFile
        )

        load()
        Self.restrictPermissions(of: indexFile, to: 0o600)
    }

    /// One-time migration off the pre-rename `ClipKeep/` data directory
    /// (this app was ClipKeep before it became MacShelf; every other store
    /// already lives under `MacShelf/`, so this one was the odd one out).
    ///
    /// Only runs when the old directory still exists *and* the new location
    /// has no `history.json` yet (a fresh install, or a migration that
    /// already happened, both skip this). The copy is verified — decoded
    /// and checked for the same item count as the original — before the old
    /// directory is removed. If anything about the copy can't be verified,
    /// the partial copy at the new location is cleaned up (so the next
    /// launch retries) and the old `ClipKeep/` directory is left untouched:
    /// starting with an empty history is a far better outcome here than
    /// deleting someone's real clipboard history on a botched migration.
    private static func migrateFromClipKeepIfNeeded(
        support: URL, newDir: URL, newImagesDir: URL, newIndexFile: URL
    ) {
        let fm = FileManager.default
        let oldDir = support.appendingPathComponent("ClipKeep", isDirectory: true)
        guard fm.fileExists(atPath: oldDir.path) else { return }
        guard !fm.fileExists(atPath: newIndexFile.path) else { return }

        let oldIndexFile = oldDir.appendingPathComponent("history.json")
        let oldImagesDir = oldDir.appendingPathComponent("images", isDirectory: true)

        func resetNewImagesDir() {
            try? fm.removeItem(at: newImagesDir)
            try? fm.createDirectory(
                at: newImagesDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
        }

        guard let oldData = try? Data(contentsOf: oldIndexFile),
              let oldItems = try? JSONDecoder().decode([ClipboardItem].self, from: oldData)
        else {
            // No readable/decodable history.json at the old location — nothing
            // to migrate. Leave the old directory alone in case it's some
            // unrelated leftover, and just start fresh.
            return
        }

        guard (try? fm.copyItem(at: oldIndexFile, to: newIndexFile)) != nil else {
            return
        }

        if fm.fileExists(atPath: oldImagesDir.path) {
            // `copyItem` refuses to copy into a destination that already
            // exists — even an empty directory — and `createDirectory` in
            // `init()` already made an empty `images/` dir, so that has to
            // be removed (not just emptied-then-recreated) right before the
            // copy, or the copy fails every time.
            try? fm.removeItem(at: newImagesDir)
            guard (try? fm.copyItem(at: oldImagesDir, to: newImagesDir)) != nil else {
                // Images failed to copy — don't leave a history.json that
                // references image files which aren't there. Recreate an
                // empty images/ dir so the store still has a valid one.
                try? fm.removeItem(at: newIndexFile)
                resetNewImagesDir()
                return
            }
        }

        // Verify before trusting the copy: it has to decode, and it has to
        // have exactly as many items as the original.
        guard let newData = try? Data(contentsOf: newIndexFile),
              let newItems = try? JSONDecoder().decode([ClipboardItem].self, from: newData),
              newItems.count == oldItems.count
        else {
            try? fm.removeItem(at: newIndexFile)
            resetNewImagesDir()
            return
        }

        // Verified — lock down the migrated copies (copied files/dirs don't
        // necessarily keep the source's exact mode) and retire the old dir.
        restrictPermissions(of: newImagesDir, to: 0o700)
        if let files = try? fm.contentsOfDirectory(atPath: newImagesDir.path) {
            for f in files {
                restrictPermissions(of: newImagesDir.appendingPathComponent(f), to: 0o600)
            }
        }
        restrictPermissions(of: newIndexFile, to: 0o600)

        try? fm.removeItem(at: oldDir)
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
