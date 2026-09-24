import Foundation

/// A bundled city, used for offline search and nearest-city lookups.
///
/// Generated from GeoNames (CC BY 4.0) by `scripts/build_cities.py`.
struct City: Identifiable, Equatable {
    let name: String
    /// ISO 3166-1 alpha-2 code, e.g. "MA".
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
    let population: Int
    /// Case/diacritic-folded `name`, precomputed at load for fast search.
    let foldedName: String

    var id: String { "\(name)|\(country)" }
    var displayName: String { "\(name), \(country)" }
    var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }
}

extension City: Codable {
    private enum CodingKeys: String, CodingKey {
        case name = "n"
        case country = "c"
        case latitude = "la"
        case longitude = "lo"
        case timeZoneIdentifier = "tz"
        case population = "p"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        country = try container.decode(String.self, forKey: .country)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        population = try container.decode(Int.self, forKey: .population)
        foldedName = City.fold(name)
    }

    /// "Tétouan" → "tetouan", "İzmir" → "izmir" — search input is folded the
    /// same way, so typing plain ASCII finds accented names.
    static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}

/// The offline city database bundled with the app.
enum CityDatabase {

    /// All bundled cities, sorted by population (desc). Empty only if the
    /// resource is missing or corrupt — tests assert this never regresses.
    static let cities: [City] = load()

    // MARK: - Search

    /// Offline, diacritic-insensitive city search, ranked prefix > word-start
    /// > substring, then by population. Requires at least two characters.
    static func search(_ query: String, limit: Int = 8) -> [City] {
        let folded = City.fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard folded.count >= 2 else { return [] }

        var matches: [(city: City, rank: Int)] = []
        for city in cities where city.foldedName.count >= folded.count {
            let rank: Int
            if city.foldedName.hasPrefix(folded) {
                rank = 0
            } else if city.foldedName.contains(" " + folded) {
                rank = 1
            } else if city.foldedName.contains(folded) {
                rank = 2
            } else {
                continue
            }
            matches.append((city, rank))
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.city.population != rhs.city.population {
                    return lhs.city.population > rhs.city.population
                }
                return lhs.city.name < rhs.city.name
            }
            .prefix(limit)
            .map(\.city)
    }

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
            name: city.displayName,
            latitude: city.latitude,
            longitude: city.longitude,
            timeZoneIdentifier: city.timeZoneIdentifier
        )
    }

    /// A place at manually-entered coordinates: the nearest notable bundled
    /// city supplies the time zone and — unless a custom name is given — a
    /// "Near …" label. Fully offline.
    static func manualPlace(name: String?, latitude: Double, longitude: Double) -> Place {
        let nearby = nearestNotable(toLatitude: latitude, longitude: longitude)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = !trimmed.isEmpty
            ? trimmed
            : nearby.map { "Near \($0.displayName)" } ?? "Custom location"
        let timeZone = nearby?.timeZoneIdentifier ?? TimeZone.current.identifier

        return Place(
            name: label,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZone
        )
    }

    /// A detected location named after its nearest notable bundled city — used
    /// when the geocoder is unreachable. Keeps the precise fix coordinates;
    /// only the label and time zone come from the city.
    static func nearestCityPlace(latitude: Double, longitude: Double) -> Place {
        guard let nearby = nearestNotable(toLatitude: latitude, longitude: longitude) else {
            return Place(
                name: "Current location",
                latitude: latitude,
                longitude: longitude,
                timeZoneIdentifier: TimeZone.current.identifier
            )
        }
        return Place(
            name: "Near \(nearby.displayName)",
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: nearby.timeZoneIdentifier
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
