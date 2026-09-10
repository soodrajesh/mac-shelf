import SwiftUI

/// Shown in place of a gated tab's real content when MacShelf Pro isn't
/// licensed — a clear upsell rather than a silently-disabled tab, same
/// spirit as MacGroom's Pro-gated views. Compact: this popover's tabs are
/// 260×190, so this has to read at a glance, not as a full marketing panel.
struct UnlockProView: View {
    let feature: String
    let systemImage: String
    var onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            Image(systemName: "lock.fill")
                .appFont(.title2)
                .foregroundStyle(.secondary)

            Text("MacShelf Pro")
                .appFont(.headline)

            Text("\(feature) needs MacShelf Pro.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Unlock Pro…", action: onUnlock)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.accentColor)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 260, height: 190, alignment: .center)
    }
}
