import Adhan
import Foundation

/// The six displayed rows: the five obligatory prayers plus sunrise (Shuruq).
enum PrayerKey: String, CaseIterable, Identifiable {
    case fajr
    case sunrise
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: String { rawValue }

    var displayName: String {
        Localization.shared.string("prayer.\(rawValue)")
    }

    /// Distinct celestial SF Symbol representing the prayer's time of day.
    var symbolName: String {
        switch self {
        case .fajr: return "sun.horizon.fill"
        case .sunrise: return "sunrise.fill"
        case .dhuhr: return "sun.max.fill"
        case .asr: return "sun.haze.fill"
        case .maghrib: return "sunset.fill"
        case .isha: return "moon.stars.fill"
        }
    }
}

/// One prayer and its time as an absolute instant.
struct PrayerEntry: Identifiable, Equatable {
    let key: PrayerKey
    let date: Date

    var id: String { key.rawValue }
}

/// A place for which prayer times are calculated.
struct Place: Codable, Equatable, Identifiable {
    /// How a place was chosen — shown in the UI, and `.detected` places are
    /// refreshed automatically when the Mac starts or wakes.
    enum Source: String, Codable {
        case city
        case detected
        case coordinates
    }

    /// Display name, e.g. "Casablanca, Morocco".
    let name: String
    /// Arabic display name, e.g. "الدار البيضاء، المغرب", when known.
    let arabicName: String?
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
    /// ISO 3166-1 alpha-2 code when known ("MA"), used for the flag emoji.
    let countryCode: String?
    /// Nil for places saved before sources were tracked.
    let source: Source?

    var id: String { "\(latitude),\(longitude)" }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    var flagEmoji: String {
        CountryFlag.emoji(for: countryCode)
    }

    /// The name in the active UI language.
    var displayName: String {
        Localization.shared.isArabic ? arabicName ?? name : name
    }

    init(
        name: String,
        arabicName: String? = nil,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        countryCode: String? = nil,
        source: Source? = nil
    ) {
        self.name = name
        self.arabicName = arabicName
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.countryCode = countryCode
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case name, arabicName, latitude, longitude, timeZoneIdentifier, countryCode, source
    }

    /// Decodes newer fields optionally so places persisted by earlier
    /// versions of the app keep loading after upgrade.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        arabicName = try container.decodeIfPresent(String.self, forKey: .arabicName)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        source = try? container.decodeIfPresent(Source.self, forKey: .source)
    }
}

/// Stable string form for UserDefaults persistence.
///
/// Deliberately *not* `RawRepresentable`: a type that is both `Codable` and
/// `RawRepresentable` with a `String` raw value gets its `Encodable` witness
/// from the stdlib's RawRepresentable extension, so a rawValue that encodes
/// `self` recurses forever and overflows the stack (fixed after a real crash).
extension Place {
    /// JSON-encoded representation suitable for UserDefaults.
    var persistedValue: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Restores a place previously stored via `persistedValue`.
    init?(persistedValue: String) {
        guard let data = persistedValue.data(using: .utf8),
              let place = try? JSONDecoder().decode(Place.self, from: data) else { return nil }
        self = place
    }
}

/// Regional calculation presets, one-to-one with Adhan's `CalculationMethod`.
enum CalculationMethodChoice: String, CaseIterable, Identifiable {
    case muslimWorldLeague
    case egyptian
    case karachi
    case ummAlQura
    case dubai
    case qatar
    case kuwait
    case moonsightingCommittee
    case singapore
    case turkey
    case tehran
    case northAmerica

    var id: String { rawValue }

    var displayName: String {
        Localization.shared.string("method.\(rawValue)")
    }

    var adhanParameters: CalculationParameters {
        switch self {
        case .muslimWorldLeague: return CalculationMethod.muslimWorldLeague.params
        case .egyptian: return CalculationMethod.egyptian.params
        case .karachi: return CalculationMethod.karachi.params
        case .ummAlQura: return CalculationMethod.ummAlQura.params
        case .dubai: return CalculationMethod.dubai.params
        case .qatar: return CalculationMethod.qatar.params
        case .kuwait: return CalculationMethod.kuwait.params
        case .moonsightingCommittee: return CalculationMethod.moonsightingCommittee.params
        case .singapore: return CalculationMethod.singapore.params
        case .turkey: return CalculationMethod.turkey.params
        case .tehran: return CalculationMethod.tehran.params
        case .northAmerica: return CalculationMethod.northAmerica.params
        }
    }

    // MARK: - Location default

    /// The convention each country's official schedule follows. Countries
    /// not listed — the Levant, Europe, most of Africa, … — use Muslim World
    /// League, the common international default (and the library's own).
    private static let countryMethods: [String: CalculationMethodChoice] = [
        // Arabian Peninsula.
        "SA": .ummAlQura,
        "AE": .dubai,
        "QA": .qatar,
        "KW": .kuwait,
        // The Nile valley and its neighbours follow the Egyptian authority.
        "EG": .egyptian,
        "SD": .egyptian,
        "LY": .egyptian,
        "SO": .egyptian,
        // South Asia.
        "PK": .karachi,
        "IN": .karachi,
        "BD": .karachi,
        "AF": .karachi,
        "LK": .karachi,
        // MUIS (Singapore), JAKIM (Malaysia), Kemenag (Indonesia) and Brunei
        // all share adhan's Singapore angles (20°/18°).
        "SG": .singapore,
        "MY": .singapore,
        "ID": .singapore,
        "BN": .singapore,
        // State-specific authorities.
        "TR": .turkey,
        "IR": .tehran,
        "US": .northAmerica,
        "CA": .northAmerica,
    ]

    /// The method selected by default for a place: its country's convention
    /// when known, otherwise Muslim World League. Accepts lowercase codes.
    static func defaultMethod(forCountryCode code: String?) -> CalculationMethodChoice {
        guard let code else { return .muslimWorldLeague }
        return countryMethods[code.uppercased()] ?? .muslimWorldLeague
    }
}

/// Asr juristic method.
enum AsrMadhab: String, CaseIterable, Identifiable {
    /// Earlier Asr (Shafi, Maliki, Hanbali).
    case shafi
    /// Later Asr.
    case hanafi

    var id: String { rawValue }

    var displayName: String {
        Localization.shared.string("madhab.\(rawValue)")
    }
}

/// Thin wrapper over adhan-swift — the only file that imports `Adhan`.
///
/// All returned times are absolute instants; display them with `place.timeZone`.
enum PrayerEngine {
    /// Computes the six times for the civil day (at `place`) containing `date`.
    ///
    /// The day is resolved in the *place's* time zone, so a Mac in Paris can
    /// show correct Makkah wall-clock times for Makkah's calendar day.
    static func entries(on date: Date, place: Place, method: CalculationMethodChoice, madhab: AsrMadhab) -> [PrayerEntry]? {
        let coordinates = Adhan.Coordinates(latitude: place.latitude, longitude: place.longitude)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        var parameters = method.adhanParameters
        parameters.madhab = madhab == .hanafi ? .hanafi : .shafi
        parameters.highLatitudeRule = .recommended(for: coordinates)

        guard let times = Adhan.PrayerTimes(coordinates: coordinates, date: components, calculationParameters: parameters) else {
            return nil
        }

        return [
            PrayerEntry(key: .fajr, date: times.fajr),
            PrayerEntry(key: .sunrise, date: times.sunrise),
            PrayerEntry(key: .dhuhr, date: times.dhuhr),
            PrayerEntry(key: .asr, date: times.asr),
            PrayerEntry(key: .maghrib, date: times.maghrib),
            PrayerEntry(key: .isha, date: times.isha),
        ]
    }
}
