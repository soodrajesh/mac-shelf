import SwiftUI

struct StatsView: View {
    @ObservedObject var stats: StatsController

    private var secondaryColor: Color { .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statRow(icon: "cpu", label: "CPU", value: stats.cpuText, high: stats.cpuHigh)
            statRow(icon: "memorychip", label: "Memory", value: stats.memText, high: stats.memHigh)

            detailRow(icon: "gauge", text: stats.memDetail)
            detailRow(icon: "flame", text: stats.topProcessText)

            Divider()

            categoryRow(category: "wifi", down: stats.netDownText, up: stats.netUpText)
            categoryRow(category: "internaldrive", down: stats.diskReadText, up: stats.diskWriteText)

            detailRow(icon: "chart.pie", text: stats.diskCapacityText)

            Spacer(minLength: 0)

            Button(action: stats.freeMemory) {
                Text(stats.freeMemStatus)
                    .appFont(.callout, weight: .medium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Color(.controlBackgroundColor))
                    .foregroundStyle(.primary)
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .disabled(stats.freeMemInProgress)
        }
        .frame(width: 260, height: 190, alignment: .top)
    }

    private func statRow(icon: String, label: String, value: String, high: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .appFont(.callout)
                .foregroundColor(secondaryColor)
                .frame(width: 14)
            Text(label)
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
            Spacer()
            if high {
                Image(systemName: "exclamationmark.triangle.fill")
                    .appFont(.caption2)
                    .foregroundStyle(Color.red)
                    .accessibilityHidden(true)
            }
            Text(value)
                .appFont(.statValue, weight: .bold, design: .rounded)
                .foregroundStyle(high ? Color.red : Color.primary)
                .accessibilityLabel("\(label) \(value)\(high ? ", high" : "")")
        }
    }

    /// A leading icon on every row (not just network/disk) so each line
    /// reads at a glance without parsing the text first.
    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .appFont(.caption)
                .foregroundColor(secondaryColor)
                .frame(width: 14)
            Text(text)
                .appFont(.caption)
                .foregroundColor(secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A leading category glyph (wifi antenna for network, drive icon for
    /// disk) makes the row identity obvious at a glance — the down/up
    /// arrows alone looked identical between the network and disk rows.
    private func categoryRow(category: String, down: String, up: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: category)
                .appFont(.subheadline)
                .foregroundColor(secondaryColor)
                .frame(width: 14)

            HStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .appFont(.caption2, weight: .bold)
                    .foregroundColor(secondaryColor)
                Text(down)
                    .appFont(.subheadline, weight: .medium)
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .appFont(.caption2, weight: .bold)
                    .foregroundColor(secondaryColor)
                Text(up)
                    .appFont(.subheadline, weight: .medium)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
    }
}
