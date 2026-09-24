import XCTest
@testable import Miqat

final class PrayerEngineTests: XCTestCase {

    /// DateFormatter pinned to a place's time zone with POSIX locale, so
    /// expectations read exactly like a wall clock in that city.
    private func formatter(timeZone identifier: String, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: identifier)!
        formatter.dateFormat = format
        return formatter
    }

    // MARK: - Reference data

    /// Spot-check against the official Umm al-Qura timetable for Makkah
    /// (ummulqura.org.sa), as compiled in the batoulapps/adhan test suite
    /// (source values adjusted ±1 minute).
    func testMakkahUmmAlQuraReferenceTimes() {
        let place = Place(name: "Makkah", latitude: 21.427009, longitude: 39.828685, timeZoneIdentifier: "Asia/Riyadh")
        let formatter = formatter(timeZone: "Asia/Riyadh", format: "M/d/yyyy h:mm:ss a")
        let noon = formatter.date(from: "3/5/2016 12:00:00 PM")!

        let expected: [PrayerKey: String] = [
            .fajr: "5:22:00 AM",
            .sunrise: "6:38:00 AM",
            .dhuhr: "12:32:00 PM",
            .asr: "3:55:00 PM",
            .maghrib: "6:27:00 PM",
            .isha: "7:57:00 PM",
        ]

        let entries = PrayerEngine.entries(on: noon, place: place, method: .ummAlQura, madhab: .shafi)
        XCTAssertNotNil(entries)

        for entry in entries! {
            let expectedDate = formatter.date(from: "3/5/2016 \(expected[entry.key]!)")!
            XCTAssertEqual(
                entry.date.timeIntervalSince(expectedDate), 0, accuracy: 61,
                "\(entry.key.displayName) differs from the Umm al-Qura timetable"
            )
        }
    }

    // MARK: - Structure

    func testEntriesAreCompleteAndOrdered() {
        let place = Place(name: "Casablanca", latitude: 33.5731, longitude: -7.5898, timeZoneIdentifier: "Africa/Casablanca")
        let formatter = formatter(timeZone: "Africa/Casablanca", format: "MM/dd/yyyy")
        let day = formatter.date(from: "09/24/2026")!

        let entries = PrayerEngine.entries(on: day, place: place, method: .muslimWorldLeague, madhab: .shafi)!
        let dates = entries.map(\.date)

        XCTAssertEqual(entries.map(\.key), PrayerKey.allCases)
        XCTAssertEqual(dates, dates.sorted(), "prayer times must be strictly ordered within the day")
    }

    func testHanafiAsrIsLaterThanShafi() {
        let place = Place(name: "Karachi", latitude: 24.8607, longitude: 67.0011, timeZoneIdentifier: "Asia/Karachi")
        let formatter = formatter(timeZone: "Asia/Karachi", format: "MM/dd/yyyy")
        let day = formatter.date(from: "09/24/2026")!

        let shafi = PrayerEngine.entries(on: day, place: place, method: .karachi, madhab: .shafi)!
        let hanafi = PrayerEngine.entries(on: day, place: place, method: .karachi, madhab: .hanafi)!

        func asr(in entries: [PrayerEntry]) -> Date {
            entries.first { $0.key == .asr }!.date
        }

        XCTAssertGreaterThan(asr(in: hanafi), asr(in: shafi), "Hanafi Asr must be later than Shafi Asr")

        // The madhab only affects Asr; everything else stays identical.
        for key in PrayerKey.allCases where key != .asr {
            XCTAssertEqual(
                shafi.first { $0.key == key }!.date,
                hanafi.first { $0.key == key }!.date,
                "\(key.displayName) should not depend on the madhab"
            )
        }
    }

    /// The civil day must be resolved in the *place's* time zone: 14:00 UTC on
    /// Sep 23 is already Sep 24 in Auckland, so the schedule must be Sep 24's.
    func testDayIsResolvedInPlaceTimeZone() {
        let place = Place(name: "Auckland", latitude: -36.8485, longitude: 174.7633, timeZoneIdentifier: "Pacific/Auckland")

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = utc.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 14))!

        let entries = PrayerEngine.entries(on: instant, place: place, method: .muslimWorldLeague, madhab: .shafi)!

        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!

        let fajrDay = auckland.component(.day, from: entries[0].date)
        XCTAssertEqual(fajrDay, 24, "schedule should be computed for Auckland's Sep 24, not the Mac's Sep 23")
    }
}
