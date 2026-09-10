import SwiftUI

struct NotepadView: View {
    @ObservedObject var store: NotepadStore
    @State private var confirmClear = false
    @State private var copiedFlash = false
    @State private var focusEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NotepadTextView(text: $store.text, focusOnAppear: focusEditor)
                .padding(6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

            HStack(spacing: 8) {
                Text(copiedFlash ? "Copied" : "Saved automatically")
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Copy") {
                    store.copyToPasteboard()
                    copiedFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copiedFlash = false
                    }
                }
                .appFont(.caption, weight: .semibold)
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: copiedFlash)

                Button("Clear") {
                    if store.text.isEmpty {
                        return
                    }
                    confirmClear = true
                }
                .appFont(.caption, weight: .medium)
                .buttonStyle(.plain)
                .foregroundStyle(store.text.isEmpty ? Color.secondary : Color.red)
                .disabled(store.text.isEmpty)
            }
        }
        .padding(4)
        .frame(width: 280, height: 220, alignment: .top)
        .onAppear {
            focusEditor = true
        }
        .confirmationDialog("Clear all notepad text?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                store.clear()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
