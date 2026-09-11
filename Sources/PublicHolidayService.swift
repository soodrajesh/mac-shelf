import Foundation

/// One country in the "Public Holidays" picker. Codes are ISO 3166-1
/// alpha-2, matching what the Nager.Date public holiday API expects.
struct HolidayCountry: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }

    /// A broad, curated set of countries Nager.Date reliably covers —
    /// not exhaustive, but enough that most users find their own.
    static let supportedCountries: [HolidayCountry] = [
        HolidayCountry(code: "AR", name: "Argentina"),
        HolidayCountry(code: "AT", name: "Austria"),
        HolidayCountry(code: "AU", name: "Australia"),
        HolidayCountry(code: "BE", name: "Belgium"),
        HolidayCountry(code: "BR", name: "Brazil"),
        HolidayCountry(code: "CA", name: "Canada"),
        HolidayCountry(code: "CH", name: "Switzerland"),
        HolidayCountry(code: "CL", name: "Chile"),
        HolidayCountry(code: "CO", name: "Colombia"),
        HolidayCountry(code: "CZ", name: "Czechia"),
        HolidayCountry(code: "DE", name: "Germany"),
        HolidayCountry(code: "DK", name: "Denmark"),
        HolidayCountry(code: "EE", name: "Estonia"),
        HolidayCountry(code: "ES", name: "Spain"),
        HolidayCountry(code: "FI", name: "Finland"),
        HolidayCountry(code: "FR", name: "France"),
        HolidayCountry(code: "GB", name: "United Kingdom"),
        HolidayCountry(code: "GR", name: "Greece"),
        HolidayCountry(code: "HR", name: "Croatia"),
        HolidayCountry(code: "HU", name: "Hungary"),
        HolidayCountry(code: "IE", name: "Ireland"),
        HolidayCountry(code: "IN", name: "India"),
        HolidayCountry(code: "IT", name: "Italy"),
        HolidayCountry(code: "JP", name: "Japan"),
        HolidayCountry(code: "LT", name: "Lithuania"),
        HolidayCountry(code: "LU", name: "Luxembourg"),
        HolidayCountry(code: "LV", name: "Latvia"),
        HolidayCountry(code: "MX", name: "Mexico"),
        HolidayCountry(code: "NL", name: "Netherlands"),
        HolidayCountry(code: "NO", name: "Norway"),
        HolidayCountry(code: "NZ", name: "New Zealand"),
        HolidayCountry(code: "PL", name: "Poland"),
        HolidayCountry(code: "PT", name: "Portugal"),
        HolidayCountry(code: "RO", name: "Romania"),
        HolidayCountry(code: "RS", name: "Serbia"),
        HolidayCountry(code: "SE", name: "Sweden"),
        HolidayCountry(code: "SG", name: "Singapore"),
        HolidayCountry(code: "SI", name: "Slovenia"),
        HolidayCountry(code: "SK", name: "Slovakia"),
        HolidayCountry(code: "TR", name: "Turkey"),
        HolidayCountry(code: "UA", name: "Ukraine"),
        HolidayCountry(code: "US", name: "United States"),
        HolidayCountry(code: "ZA", name: "South Africa")
    ].sorted { $0.name < $1.name }

    /// Infers a starting default from the user's macOS region so the
    /// calendar has sensible highlights on first launch without asking —
    /// falls back to "no country selected" (highlights off) if the
    /// system region isn't one we support.
    static var defaultCountryCode: String {
        guard let region = Locale.current.region?.identifier,
              supportedCountries.contains(where: { $0.code == region }) else {
            return ""
        }
        return region
    }
}

/// Fetches and caches public holidays per country/year from Nager.Date's
/// free, unauthenticated public holiday API
/// (`https://date.nager.at/api/v3/PublicHolidays/{year}/{countryCode}`),
/// replacing the old Ireland-only algorithmic calculator so any supported
/// country can be selected in Settings. Disk-cached in `UserDefaults` so
/// the calendar still highlights correctly offline after the first fetch,
/// and a failed/offline fetch just means no highlight for that year rather
/// than a crash or error state — holidays are a nice-to-have overlay, not
/// core functionality.
@MainActor
final class PublicHolidayStore: ObservableObject {
    private struct HolidayKey: Hashable {
        let year: Int
        let month: Int
        let day: Int
    }

    @Published private var holidayKeys: Set<HolidayKey> = []
    private var loadedYearKeys: Set<String> = [] // "CC-YYYY" already requested this session
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    func isHoliday(_ date: Date) -> Bool {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return false }
        return holidayKeys.contains(HolidayKey(year: year, month: month, day: day))
    }

    /// Call when the visible country or calendar grid changes. `years`
    /// should cover every year the currently-displayed 6-row grid can
    /// touch (usually one, occasionally two at a Dec/Jan boundary).
    func ensureLoaded(country: String, years: Set<Int>) {
        guard !country.isEmpty else { return }
        for year in years {
            let cacheKey = "\(country)-\(year)"
            guard !loadedYearKeys.contains(cacheKey) else { continue }
            loadedYearKeys.insert(cacheKey)

            if let cached = Self.readDiskCache(country: country, year: year) {
                holidayKeys.formUnion(cached)
            }
            Task { await self.fetchYear(country: country, year: year) }
        }
    }

    /// Called when the user switches country — old country's highlights
    /// must not linger. Disk cache is kept (cheap, and avoids re-fetching
    /// if they switch back).
    func reset() {
        holidayKeys = []
        loadedYearKeys = []
    }

    private func fetchYear(country: String, year: Int) async {
        guard let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(country)") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        struct APIHoliday: Decodable { let date: String }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode([APIHoliday].self, from: data)

            var keys: Set<HolidayKey> = []
            for item in decoded {
                let parts = item.date.split(separator: "-")
                guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { continue }
                keys.insert(HolidayKey(year: y, month: m, day: d))
            }

            Self.writeDiskCache(country: country, year: year, dates: keys.map { ($0.year, $0.month, $0.day) })
            holidayKeys.formUnion(keys)
        } catch {
            // Offline or API hiccup — silently keep whatever's cached
            // (possibly nothing). Not worth surfacing an error for an
            // overlay feature.
        }
    }

    // MARK: - Disk cache (UserDefaults, small — a year's holidays is ~15 dates)

    private static func cacheDefaultsKey(country: String, year: Int) -> String {
        "publicHolidayCache.\(country).\(year)"
    }

    private static func readDiskCache(country: String, year: Int) -> Set<HolidayKey>? {
        guard let stored = UserDefaults.standard.array(forKey: cacheDefaultsKey(country: country, year: year)) as? [String] else {
            return nil
        }
        var keys: Set<HolidayKey> = []
        for entry in stored {
            let parts = entry.split(separator: "-")
            guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { continue }
            keys.insert(HolidayKey(year: y, month: m, day: d))
        }
        return keys
    }

    private static func writeDiskCache(country: String, year: Int, dates: [(Int, Int, Int)]) {
        let encoded = dates.map { "\($0.0)-\($0.1)-\($0.2)" }
        UserDefaults.standard.set(encoded, forKey: cacheDefaultsKey(country: country, year: year))
    }
}
