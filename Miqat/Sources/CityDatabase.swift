import Foundation

/// ISO 3166-1 alpha-2 code → regional-indicator flag emoji ("MA" → 🇲🇦).
/// Falls back to 📍 for anything that isn't a two-letter uppercase code.
enum CountryFlag {
    static func emoji(for countryCode: String?) -> String {
        guard let code = countryCode,
              code.count == 2,
              code.allSatisfy({ $0.isASCII && $0.isUppercase }) else {
            return "📍"
        }

        let scalars = code.unicodeScalars.map { Unicode.Scalar(0x1F1E6 + $0.value - 65)! }
        return String(String.UnicodeScalarView(scalars))
    }
}

/// Country names in both UI languages, from the system's region tables —
/// no bundled data needed ("SY" → "Syria" / "سوريا").
enum CountryName {
    private static let english = Locale(identifier: "en_US")
    private static let arabic = Locale(identifier: "ar")

    static func english(_ code: String) -> String {
        english.localizedString(forRegionCode: code) ?? code
    }

    static func arabic(_ code: String) -> String {
        arabic.localizedString(forRegionCode: code) ?? english(code)
    }

    /// The name in the active UI language.
    static func localized(_ code: String) -> String {
        Localization.shared.isArabic ? arabic(code) : english(code)
    }

    /// Common short forms the region tables don't carry.
    static let aliases: [String: [String]] = [
        "AE": ["UAE", "Emirates", "الإمارات"],
        "SA": ["KSA", "Saudi", "السعودية"],
        "US": ["USA", "America", "أمريكا"],
        "GB": ["UK", "England", "Britain", "بريطانيا"],
        "PS": ["Palestine", "فلسطين"],
        "NL": ["Holland", "هولندا"],
        "CI": ["Ivory Coast"],
    ]
}

/// Search normalization shared by city and country matching.
enum SearchText {
    /// Folds case, Latin diacritics and Arabic spelling variants, so plain
    /// input finds "Tétouan", and "مكه" / "مكة" / "مَكَّة" all match.
    static func normalize(_ string: String) -> String {
        var folded = string
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard folded.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) else {
            return folded
        }
        folded.unicodeScalars.removeAll { scalar in
            (0x064B...0x065F).contains(scalar.value) // harakat, tanween, shadda, sukun
                || scalar.value == 0x0670            // superscript alef
                || scalar.value == 0x0640            // tatweel
        }
        let replacements: [Character: Character] = [
            "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا",
            "ة": "ه", "ى": "ي", "ؤ": "و", "ئ": "ي",
        ]
        return String(folded.map { replacements[$0] ?? $0 })
    }

    /// 0 = prefix, 1 = word start (after a space or dash, or after the
    /// Arabic article "ال"), 2 = substring; nil = no match. Both sides must
    /// already be normalized.
    static func rank(of query: String, in key: String, allowSubstring: Bool = true) -> Int? {
        guard key.count >= query.count else { return nil }
        if key.hasPrefix(query) || key.hasPrefix("ال" + query) { return 0 }
        if key.contains(" " + query) || key.contains("-" + query) || key.contains(" ال" + query) { return 1 }
        if allowSubstring, key.contains(query) { return 2 }
        return nil
    }
}

/// A bundled city, used for offline search and nearest-city lookups.
///
/// Generated from GeoNames (CC BY 4.0) by `scripts/build_cities.py`.
struct City: Identifiable, Equatable {
    let name: String
    /// Arabic name when GeoNames has one ("Rabat" → "الرباط").
    let arabicName: String?
    /// ISO 3166-1 alpha-2 code, e.g. "MA".
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
    let population: Int
    /// Normalized English name, Arabic name and alternate Arabic spellings,
    /// precomputed at load for fast search.
    let searchKeys: [String]

    var id: String { "\(name)|\(country)|\(latitude)" }
    var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }
    var flagEmoji: String { CountryFlag.emoji(for: country) }

    /// City name in the active UI language (Latin when no Arabic exists).
    var localizedName: String {
        Localization.shared.isArabic ? arabicName ?? name : name
    }

    /// "Damascus, Syria" / "دمشق، سوريا".
    var displayName: String {
        Localization.shared.isArabic
            ? "\(arabicName ?? name)، \(CountryName.arabic(country))"
            : "\(name), \(CountryName.english(country))"
    }
}

extension City: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name = "n"
        case arabicName = "a"
        case aliases = "x"
        case country = "c"
        case latitude = "la"
        case longitude = "lo"
        case timeZoneIdentifier = "tz"
        case population = "p"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        arabicName = try container.decodeIfPresent(String.self, forKey: .arabicName)
        country = try container.decode(String.self, forKey: .country)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        population = try container.decode(Int.self, forKey: .population)

        let aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        var keys: [String] = []
        for spelling in [name] + [arabicName].compactMap { $0 } + aliases {
            let key = SearchText.normalize(spelling)
            if !key.isEmpty, !keys.contains(key) { keys.append(key) }
        }
        searchKeys = keys
    }
}

/// The offline city database bundled with the app.
enum CityDatabase {

    /// All bundled cities, sorted by population (desc). Empty only if the
    /// resource is missing or corrupt — tests assert this never regresses.
    static let cities: [City] = load()

    // MARK: - Search

    /// Offline search by city or country, in English or Arabic.
    ///
    /// - "casa", "الدار", "مكه" → cities by name, ranked prefix > word start
    ///   > substring, then by population.
    /// - "Syria", "سوريا" → that country's largest cities (after any city
    ///   whose name starts with the query).
    /// - "Tripoli, Lebanon", "طرابلس لبنان" → city narrowed to a country.
    ///
    /// Requires at least two characters.
    static func search(_ query: String, limit: Int = 40) -> [City] {
        let normalized = SearchText.normalize(query)
        guard normalized.count >= 2 else { return [] }

        // Explicit "city, country".
        if let comma = normalized.firstIndex(where: { $0 == "," || $0 == "،" }) {
            let cityPart = normalized[..<comma].trimmingCharacters(in: .whitespaces)
            let countryPart = normalized[normalized.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            let countries = Set(matchingCountries(countryPart))
            if !cityPart.isEmpty, !countries.isEmpty {
                return rankedCities(matching: cityPart, in: countries, limit: limit).map(\.city)
            }
            return rankedCities(matching: cityPart.isEmpty ? countryPart : cityPart, in: nil, limit: limit).map(\.city)
        }

        let byName = rankedCities(matching: normalized, in: nil, limit: limit)
        let countries = matchingCountries(normalized)

        var results = byName.filter { $0.rank < 2 }.map(\.city)
        if !countries.isEmpty {
            var seen = Set(results.map(\.id))
            for code in countries {
                for city in cities where city.country == code && !seen.contains(city.id) {
                    results.append(city)
                    seen.insert(city.id)
                    if results.count >= limit { break }
                }
            }
        }
        results += byName.filter { $0.rank >= 2 }.map(\.city).filter { city in
            !results.contains { $0.id == city.id }
        }

        // "city country" without a comma: peel trailing words off as a country.
        if results.isEmpty {
            let words = normalized.split(separator: " ")
            for split in stride(from: words.count - 1, through: 1, by: -1) {
                let countryPart = words[split...].joined(separator: " ")
                let codes = Set(matchingCountries(countryPart))
                guard !codes.isEmpty else { continue }
                let cityPart = words[..<split].joined(separator: " ")
                let narrowed = rankedCities(matching: cityPart, in: codes, limit: limit).map(\.city)
                if !narrowed.isEmpty { return narrowed }
            }
        }

        return Array(results.prefix(limit))
    }

    /// Country codes whose English/Arabic name or alias starts with the
    /// query (or has a word that does), best match first.
    static func matchingCountries(_ normalizedQuery: String) -> [String] {
        guard normalizedQuery.count >= 2 else { return [] }
        return countryIndex
            .compactMap { entry -> (code: String, rank: Int)? in
                let rank = entry.keys
                    .compactMap { SearchText.rank(of: normalizedQuery, in: $0, allowSubstring: false) }
                    .min()
                return rank.map { (entry.code, $0) }
            }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.code < $1.code }
            .map(\.code)
    }

    private static func rankedCities(
        matching query: String,
        in countries: Set<String>?,
        limit: Int
    ) -> [(city: City, rank: Int)] {
        var matches: [(city: City, rank: Int)] = []
        for city in cities {
            if let countries, !countries.contains(city.country) { continue }
            let rank = city.searchKeys.compactMap { SearchText.rank(of: query, in: $0) }.min()
            if let rank { matches.append((city, rank)) }
        }

        // `cities` is already population-descending; a stable sort by rank
        // keeps that order within each rank.
        return Array(
            matches
                .enumerated()
                .sorted { $0.element.rank != $1.element.rank ? $0.element.rank < $1.element.rank : $0.offset < $1.offset }
                .map(\.element)
                .prefix(limit)
        )
    }

    /// Normalized names for every country present in the database.
    private static let countryIndex: [(code: String, keys: [String])] = {
        var codes: [String] = []
        var seen = Set<String>()
        for city in cities where seen.insert(city.country).inserted {
            codes.append(city.country)
        }
        return codes.map { code in
            let names = [CountryName.english(code), CountryName.arabic(code)]
                + (CountryName.aliases[code] ?? [])
            return (code, names.map(SearchText.normalize))
        }
    }()

    // MARK: - Nearest city

    /// Great-circle-nearest bundled city (haversine; a few ms for ~12k rows).
    static func nearest(toLatitude latitude: Double, longitude: Double) -> City? {
        var best: City?
        var bestDistance = Double.infinity

        for city in cities {
            let distance = haversineKilometers(
                from: (latitude, longitude),
                to: (city.latitude, city.longitude)
            )
            if distance < bestDistance {
                bestDistance = distance
                best = city
            }
        }
        return best
    }

    /// The most *notable* nearby city: the most populous city within a window
    /// around the true nearest one. "Near Istanbul, TR" reads far better than
    /// the administratively-nearest district ("Eminönü"), and anchors the
    /// time zone just as well.
    static func nearestNotable(toLatitude latitude: Double, longitude: Double) -> City? {
        guard let nearest = nearest(toLatitude: latitude, longitude: longitude) else { return nil }

        let nearestDistance = haversineKilometers(
            from: (latitude, longitude),
            to: (nearest.latitude, nearest.longitude)
        )
        let window = max(nearestDistance * 1.5, 25.0)

        // `cities` is population-descending, so the first hit in the window
        // is by construction the biggest city nearby.
        return cities.first { city in
            haversineKilometers(from: (latitude, longitude), to: (city.latitude, city.longitude)) <= window
        } ?? nearest
    }

    private static func haversineKilometers(
        from a: (latitude: Double, longitude: Double),
        to b: (latitude: Double, longitude: Double)
    ) -> Double {
        let radius = 6_371.0
        let deltaLatitude = (b.latitude - a.latitude) * .pi / 180
        let deltaLongitude = (b.longitude - a.longitude) * .pi / 180
        let latitudeA = a.latitude * .pi / 180
        let latitudeB = b.latitude * .pi / 180

        let h = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(latitudeA) * cos(latitudeB) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }

    // MARK: - Places

    static func place(from city: City) -> Place {
        Place(
            name: "\(city.name), \(CountryName.english(city.country))",
            arabicName: "\(city.arabicName ?? city.name)، \(CountryName.arabic(city.country))",
            latitude: city.latitude,
            longitude: city.longitude,
            timeZoneIdentifier: city.timeZoneIdentifier,
            countryCode: city.country,
            source: .city
        )
    }

    /// "Near Istanbul, Türkiye" / "قرب اسطنبول، تركيا".
    private static func nearLabels(_ city: City) -> (english: String, arabic: String) {
        (
            "Near \(city.name), \(CountryName.english(city.country))",
            "قرب \(city.arabicName ?? city.name)، \(CountryName.arabic(city.country))"
        )
    }

    /// A place at manually-entered coordinates: the nearest notable bundled
    /// city supplies the time zone and — unless a custom name is given — a
    /// "Near …" label. Fully offline.
    static func manualPlace(name: String?, latitude: Double, longitude: Double) -> Place {
        let nearby = nearestNotable(toLatitude: latitude, longitude: longitude)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let labels: (english: String, arabic: String)
        if !trimmed.isEmpty {
            labels = (trimmed, trimmed)
        } else if let nearby {
            labels = nearLabels(nearby)
        } else {
            labels = ("Custom location", "موقع مخصص")
        }

        return Place(
            name: labels.english,
            arabicName: labels.arabic,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: nearby?.timeZoneIdentifier ?? TimeZone.current.identifier,
            countryCode: nearby?.country,
            source: .coordinates
        )
    }

    /// A detected location named after its nearest notable bundled city — used
    /// when the geocoder is unreachable. Keeps the precise fix coordinates;
    /// only the label and time zone come from the city.
    static func nearestCityPlace(latitude: Double, longitude: Double) -> Place {
        guard let nearby = nearestNotable(toLatitude: latitude, longitude: longitude) else {
            return Place(
                name: "Current location",
                arabicName: "الموقع الحالي",
                latitude: latitude,
                longitude: longitude,
                timeZoneIdentifier: TimeZone.current.identifier,
                source: .detected
            )
        }
        let labels = nearLabels(nearby)
        return Place(
            name: labels.english,
            arabicName: labels.arabic,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: nearby.timeZoneIdentifier,
            countryCode: nearby.country,
            source: .detected
        )
    }

    // MARK: - Loading

    private static func load() -> [City] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        let url = bundle.url(forResource: "cities", withExtension: "json", subdirectory: "Resources")
            ?? bundle.url(forResource: "cities", withExtension: "json")
        #else
        let bundle = Bundle.main
        let url = bundle.url(forResource: "cities", withExtension: "json")
        #endif

        guard let url, let data = try? Data(contentsOf: url) else {
            NSLog("Miqat: cities.json not found in bundle \(bundle)")
            return []
        }
        do {
            return try JSONDecoder().decode([City].self, from: data)
        } catch {
            NSLog("Miqat: cities.json failed to decode — \(error)")
            return []
        }
    }
}
