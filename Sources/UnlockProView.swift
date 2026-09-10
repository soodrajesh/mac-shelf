import SwiftUI

/// Shown in place of a gated tab's real content when MacShelf Pro isn't
/// licensed — a clear upsell rather than a silently-disabled tab, same
/// spirit as MacGroom's Pro-gated views. Compact: this popover's tabs are
/// 280×220, so this has to read at a glance, not as a full marketing panel.
struct UnlockProView: View {
    let feature: String
    let systemImage: String
    var onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            IconTile(systemName: "lock.fill", tileSize: 40, symbolScale: 0.45)

            Text("MacShelf Pro")
                .appFont(.headline, weight: .bold)

            Text("\(feature) needs MacShelf Pro.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Unlock Pro…", action: onUnlock)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.appAccent)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .cardStyle(cornerRadius: 14, padding: 12)
        .frame(width: 280, height: 220, alignment: .center)
    }
}
