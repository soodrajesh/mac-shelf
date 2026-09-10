import SwiftUI

struct ClipboardListView: View {
    @ObservedObject var store: ClipboardStore
    let onSelect: (ClipboardItem) -> Void

    @State private var confirmClearAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.items.isEmpty {
                Spacer()
                Text("No clipboard history yet")
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.items.prefix(12), id: \.id) { item in
                            HStack(spacing: 4) {
                                Button(action: { onSelect(item) }) {
                                    rowContent(for: item)
                                        .padding(.horizontal, 6)
                                        .frame(height: 24)
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        store.remove(item)
                                    }
                                }

                                Button(action: { store.remove(item) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .appFont(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Delete this item")
                                .accessibilityLabel("Delete clipboard item")
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Clear All") { confirmClearAll = true }
                        .appFont(.caption2, weight: .medium)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.red)
                        .help("Delete all clipboard history")
                }
            }
        }
        .cardStyle(cornerRadius: 12, padding: 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.items.count)
        .frame(width: 280, height: 220, alignment: .top)
        .confirmationDialog("Clear all clipboard history?", isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                store.clear()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Text rows show the preview string; image rows show the actual
    /// thumbnail (loaded from the store's on-disk PNG) plus its dimensions —
    /// matching ClipKeep's own picker (`PickerRowView`) instead of a generic
    /// placeholder icon.
    @ViewBuilder
    private func rowContent(for item: ClipboardItem) -> some View {
        HStack(spacing: 6) {
            switch item.kind {
            case .text:
                Text(rowTitle(for: item))
                    .appFont(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .accessibilityLabel(rowTitle(for: item))
            case .image:
                if let f = item.imageFile, let nsImage = NSImage(contentsOf: store.imageURL(for: f)) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .cornerRadius(2)
                        .accessibilityHidden(true)
                    Text("\(Int(nsImage.size.width))×\(Int(nsImage.size.height))")
                        .appFont(.subheadline)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Copied image, \(Int(nsImage.size.width)) by \(Int(nsImage.size.height)) pixels")
                } else {
                    Image(systemName: "photo")
                        .appFont(.subheadline)
                        .foregroundStyle(.primary)
                    Text("Image")
                        .appFont(.subheadline)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Copied image")
                }
            }
            Spacer()
        }
    }

    private func rowTitle(for item: ClipboardItem) -> String {
        let flat = item.preview.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 40 ? String(flat.prefix(40)) + "…" : flat
    }
}
