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
}
