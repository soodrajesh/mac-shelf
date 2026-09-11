import SwiftUI

/// MacShelf's own identity color — vivid orange, matching the redesigned app
/// icon's gradient start (switched from an earlier magenta/pink pass).
/// Deliberately a fixed app color, not the system `Color.accentColor`, per
/// `DESIGN-SYSTEM.md`'s v2 "modern & colorful" refresh: each app in the line
/// now carries its own accent instead of defaulting to gray/blue.
/// `Color.accentColor` is still used for the one or two spots that should
/// genuinely track the user's system accent.
extension Color {
    static let appAccent = Color(red: 1.00, green: 0.42, blue: 0.02)
}

/// A small rounded-square tile behind an SF Symbol — the single change the
/// design doc calls out as doing the most to fix "monochrome" (borrowed from
/// System Settings' own sidebar). Wraps a bare `Image(systemName:)` in a
/// `Color.appAccent.opacity(0.15)` tile with the glyph tinted `Color.appAccent`.
struct IconTile: View {
    let systemName: String
    var tileSize: CGFloat = 20
    var symbolScale: CGFloat = 0.55

    var body: some View {
        RoundedRectangle(cornerRadius: tileSize * 0.32, style: .continuous)
            .fill(Color.appAccent.opacity(0.15))
            .frame(width: tileSize, height: tileSize)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: tileSize * symbolScale, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
            )
    }
}

/// A card container matching the design doc's "card-based content, real
/// depth" rule: rounded corners, a subtle shadow, and a hairline separator
/// stroke over a material fill instead of a flat solid color. Padding is
/// tighter than the doc's 16pt minimum because this app's popover tabs are a
/// fixed 280×220 — see the PR notes for that deliberate deviation.
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 12, padding: CGFloat = 10) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, padding: padding))
    }
}
