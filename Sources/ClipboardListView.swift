import SwiftUI

struct ClipboardListView: View {
    @ObservedObject var store: ClipboardStore
    let onSelect: (ClipboardItem) -> Void

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
                            Button(action: { onSelect(item) }) {
                                rowContent(for: item)
                                    .padding(.horizontal, 6)
                                    .frame(height: 22)
                                    .background(Color(.controlBackgroundColor))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(width: 260, height: 190, alignment: .top)
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
            case .image:
                if let f = item.imageFile, let nsImage = NSImage(contentsOf: store.imageURL(for: f)) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .cornerRadius(2)
                    Text("\(Int(nsImage.size.width))×\(Int(nsImage.size.height))")
                        .appFont(.subheadline)
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "photo")
                        .appFont(.subheadline)
                        .foregroundStyle(.primary)
                    Text("Image")
                        .appFont(.subheadline)
                        .foregroundStyle(.primary)
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
