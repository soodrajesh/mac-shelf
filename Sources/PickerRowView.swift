import AppKit

final class PickerRowView: NSTableCellView {
    static let textRowHeight: CGFloat = 40
    static let imageRowHeight: CGFloat = 60

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    // Side-by-side (text rows): icon leading, label vertically centered beside it.
    private var sideBySideConstraints: [NSLayoutConstraint] = []
    // Stacked (image rows): icon centered on top, label centered below it.
    private var stackedConstraints: [NSLayoutConstraint] = []

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.font = .systemFont(ofSize: 13)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
        ])

        sideBySideConstraints = [
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]

        stackedConstraints = [
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ]

        NSLayoutConstraint.activate(sideBySideConstraints)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with item: ClipboardItem, store: ClipboardStore) {
        switch item.kind {
        case .text:
            iconView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Copied text")
            label.stringValue = item.preview.replacingOccurrences(of: "\n", with: "  ⏎  ")
            label.alignment = .left
            setStacked(false)
            setAccessibilityLabel(label.stringValue)
        case .image:
            if let f = item.imageFile, let img = NSImage(contentsOf: store.imageURL(for: f)) {
                iconView.image = img
                label.stringValue = "\(Int(img.size.width))×\(Int(img.size.height))"
                setAccessibilityLabel("Copied image, \(label.stringValue) pixels")
            } else {
                iconView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "Copied image")
                label.stringValue = "Image"
                setAccessibilityLabel("Copied image")
            }
            label.alignment = .center
            setStacked(true)
        }
    }

    private func setStacked(_ stacked: Bool) {
        NSLayoutConstraint.deactivate(stacked ? sideBySideConstraints : stackedConstraints)
        NSLayoutConstraint.activate(stacked ? stackedConstraints : sideBySideConstraints)
    }
}
