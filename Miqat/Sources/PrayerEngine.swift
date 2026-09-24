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
        switch self {
        case .fajr: return "Fajr"
        case .sunrise: return "Shuruq"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
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
    /// Display name, e.g. "Casablanca, Morocco".
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String

    var id: String { "\(latitude),\(longitude)" }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
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
        switch self {
        case .muslimWorldLeague: return "Muslim World League"
        case .egyptian: return "Egyptian General Authority"
        case .karachi: return "Karachi (Islamic Sciences)"
        case .ummAlQura: return "Umm al-Qura, Makkah"
        case .dubai: return "Dubai (UAE)"
        case .qatar: return "Qatar"
        case .kuwait: return "Kuwait"
        case .moonsightingCommittee: return "Moonsighting Committee"
        case .singapore: return "Singapore & Malaysia"
        case .turkey: return "Turkey (Diyanet)"
        case .tehran: return "Tehran"
        case .northAmerica: return "ISNA (North America)"
        }
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
}

/// Asr juristic method.
enum AsrMadhab: String, CaseIterable, Identifiable {
    /// Earlier Asr (Shafi, Maliki, Hanbali).
    case shafi
    /// Later Asr.
    case hanafi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shafi: return "Shafi"
        case .hanafi: return "Hanafi"
        }
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
