import SwiftUI

struct CalendarView: View {
    @State private var displayedMonth = Date()
    @AppStorage("holidayCountryCode") private var holidayCountryCode: String = HolidayCountry.defaultCountryCode
    @StateObject private var holidayStore = PublicHolidayStore()
    let calendar = Calendar(identifier: .gregorian)
    let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        VStack(spacing: 5) {
            // Month header with prev/next navigation
            HStack {
                navButton("chevron.left", help: "Previous month", action: previousMonth)

                Spacer()

                // Tapping the label jumps back to the current month — the
                // only way back once you've navigated away with the chevrons.
                Button(action: jumpToToday) {
                    Text(monthYearFormatter.string(from: displayedMonth))
                        .appFont(.callout, weight: .semibold)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("Jump to today")

                Spacer()

                navButton("chevron.right", help: "Next month", action: nextMonth)
            }
            .frame(height: 26)

            // Day-of-week headers
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .appFont(.caption2, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 12)

            // Calendar grid — each cell is a real Date so holiday lookups
            // and month-boundary checks are correct even at year edges.
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(Array(gridDates().enumerated()), id: \.offset) { _, date in
                    dayCell(date)
                }
            }
        }
        .cardStyle(cornerRadius: 10, padding: 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: displayedMonth)
        .frame(width: 280, height: 220)
        .onAppear { loadHolidays() }
        .onChange(of: displayedMonth) { _ in loadHolidays() }
        .onChange(of: holidayCountryCode) { _ in
            holidayStore.reset()
            loadHolidays()
        }
    }

    /// Loads whichever year(s) the current 6-row grid can touch — usually
    /// one, but a grid can spill into the next/previous year at a Dec/Jan
    /// boundary (e.g. December's trailing cells reach into January).
    private func loadHolidays() {
        guard !holidayCountryCode.isEmpty else { return }
        let years = Set(gridDates().compactMap { $0 }.map { calendar.component(.year, from: $0) })
        holidayStore.ensureLoaded(country: holidayCountryCode, years: years)
    }

    /// Bigger, filled-circle month-nav buttons — the old bare 16pt chevrons
    /// read as barely-there against the card background. A tinted circle
    /// tile (same idea as `IconTile`) gives them real visual weight and a
    /// larger hit target.
    private func navButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .appFont(.callout, weight: .heavy)
                .foregroundStyle(Color.appAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.appAccent.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date = date {
            let day = calendar.component(.day, from: date)
            Text("\(day)")
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(isCurrentMonth(date) ? (isToday(date) ? Color.white : Color.primary) : Color.secondary.opacity(0.6))
                .frame(width: 22, height: 22)
                .background(isToday(date) ? Color.appAccent : Color.clear)
                .cornerRadius(5)
                .overlay(alignment: .topTrailing) {
                    if isCurrentMonth(date) && !holidayCountryCode.isEmpty && holidayStore.isHoliday(date) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 4, height: 4)
                            .offset(x: 2, y: -1)
                    }
                }
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }

    private var monthYearFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt
    }

    /// Full 6-row (42-cell) grid as real Dates, including the tail end of
    /// the previous month (leading blanks) and the start of the next
    /// month (trailing cells) — so every visible number is a real date.
    func gridDates() -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }
        let numDays = range.count
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - 1 // 0 = Sunday

        var dates: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in 1...numDays {
            dates.append(calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth))
        }

        let remaining = 42 - dates.count
        if remaining > 0, let lastOfMonth = calendar.date(byAdding: .day, value: numDays - 1, to: firstOfMonth) {
            for i in 1...remaining {
                dates.append(calendar.date(byAdding: .day, value: i, to: lastOfMonth))
            }
        }

        return dates
    }

    func isCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    func previousMonth() {
        guard let newDate = calendar.date(byAdding: .month, value: -1, to: displayedMonth) else {
            return
        }
        displayedMonth = newDate
    }

    func nextMonth() {
        guard let newDate = calendar.date(byAdding: .month, value: 1, to: displayedMonth) else {
            return
        }
        displayedMonth = newDate
    }

    func jumpToToday() {
        displayedMonth = Date()
    }
}
