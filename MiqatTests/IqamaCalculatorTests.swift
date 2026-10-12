import XCTest
@testable import Miqat

final class IqamaCalculatorTests: XCTestCase {

    private let dhuhr = Date(timeIntervalSince1970: 1_800_000_000)

    private func entries() -> [PrayerEntry] {
        [
            PrayerEntry(key: .sunrise, date: dhuhr.addingTimeInterval(-6 * 3600)),
            PrayerEntry(key: .dhuhr, date: dhuhr),
            PrayerEntry(key: .asr, date: dhuhr.addingTimeInterval(3 * 3600)),
        ]
    }

    func testPendingBetweenAdhanAndIqama() {
        let pending = IqamaCalculator.pending(today: entries(), now: dhuhr.addingTimeInterval(5 * 60))
        XCTAssertEqual(pending, .init(prayer: .dhuhr, iqama: dhuhr.addingTimeInterval(20 * 60)))
    }

    func testNothingPendingBeforeAdhanOrAfterIqama() {
        XCTAssertNil(IqamaCalculator.pending(today: entries(), now: dhuhr.addingTimeInterval(-1)))
        XCTAssertNil(IqamaCalculator.pending(today: entries(), now: dhuhr.addingTimeInterval(20 * 60)))
    }

    func testSunriseHasNoIqama() {
        let sunrise = dhuhr.addingTimeInterval(-6 * 3600)
        XCTAssertNil(IqamaCalculator.pending(today: entries(), now: sunrise.addingTimeInterval(60)))
    }

    func testCustomGapOverridesDefault() {
        let now = dhuhr.addingTimeInterval(25 * 60)
        XCTAssertNil(IqamaCalculator.pending(today: entries(), now: now))
        let pending = IqamaCalculator.pending(today: entries(), now: now, customGaps: [.dhuhr: 30])
        XCTAssertEqual(pending?.iqama, dhuhr.addingTimeInterval(30 * 60))
    }

    func testStoreClampsAndClearsOverridesAtDefault() {
        UserDefaults.standard.removeObject(forKey: "miqat.iqama.gaps")
        defer { UserDefaults.standard.removeObject(forKey: "miqat.iqama.gaps") }

        let store = PrayerScheduleStore()
        XCTAssertEqual(store.iqamaGap(for: .fajr), 25)
        store.setIqamaGap(40, for: .fajr)
        XCTAssertEqual(PrayerScheduleStore().iqamaGap(for: .fajr), 40, "persisted")
        store.setIqamaGap(999, for: .fajr)
        XCTAssertEqual(store.iqamaGap(for: .fajr), 60, "clamped")
        store.setIqamaGap(25, for: .fajr)
        XCTAssertTrue(store.iqamaGaps.isEmpty, "default clears the override")
    }

    func testWarningDefaultsAndPersistence() {
        let keys = ["miqat.iqama.warning.enabled", "miqat.iqama.warning.minutes", "miqat.iqama.warning.color"]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        defer { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

        let store = PrayerScheduleStore()
        XCTAssertTrue(store.iqamaWarningEnabled)
        XCTAssertEqual(store.iqamaWarningMinutes, 5)
        XCTAssertEqual(store.iqamaWarningColorHex, "FF3B30")

        store.iqamaWarningEnabled = false
        store.iqamaWarningMinutes = 8
        store.iqamaWarningColorHex = "00AA55"
        let reloaded = PrayerScheduleStore()
        XCTAssertFalse(reloaded.iqamaWarningEnabled)
        XCTAssertEqual(reloaded.iqamaWarningMinutes, 8)
        XCTAssertEqual(reloaded.iqamaWarningColorHex, "00AA55")
    }
}
