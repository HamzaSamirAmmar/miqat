import XCTest
@testable import Miqat

final class LocalizationTests: XCTestCase {

    override func tearDown() {
        Localization.shared.language = .system
        UserDefaults.standard.removeObject(forKey: Localization.storageKey)
        super.tearDown()
    }

    /// Every English key must have an Arabic translation and vice versa —
    /// a missing key renders as raw text in one of the languages.
    func testEnglishAndArabicTablesHaveIdenticalKeys() {
        let english = Set(Localization.tables["en"]!.keys)
        let arabic = Set(Localization.tables["ar"]!.keys)

        XCTAssertEqual(english.subtracting(arabic).sorted(), [],
                       "keys missing from Arabic: \(english.subtracting(arabic).sorted())")
        XCTAssertEqual(arabic.subtracting(english).sorted(), [],
                       "keys missing from English: \(arabic.subtracting(english).sorted())")
    }

    func testLanguageSwitchChangesPrayerNames() {
        Localization.shared.language = .english
        XCTAssertEqual(Localization.shared.string("prayer.fajr"), "Fajr")
        XCTAssertFalse(Localization.shared.isRTL)

        Localization.shared.language = .arabic
        XCTAssertEqual(Localization.shared.string("prayer.fajr"), "الفجر")
        XCTAssertEqual(Localization.shared.string("prayer.maghrib"), "المغرب")
        XCTAssertTrue(Localization.shared.isArabic)
        XCTAssertTrue(Localization.shared.isRTL)
    }

    func testArabicUsesWesternFallbackForMissingKey() {
        Localization.shared.language = .arabic
        XCTAssertEqual(Localization.shared.string("definitely.not.a.key"), "definitely.not.a.key")
    }

    func testFormatArguments() {
        Localization.shared.language = .english
        XCTAssertEqual(Localization.shared.string("next.prefix", "43m"), "in 43m")

        // The ar locale wraps substituted args in invisible bidi-isolation
        // marks (U+2068/U+2069) — strip them before comparing.
        Localization.shared.language = .arabic
        let formatted = Localization.shared.string("next.prefix", "43د")
            .replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
        XCTAssertEqual(formatted, "بعد 43د")
    }

    func testLanguagePersists() {
        Localization.shared.language = .arabic
        XCTAssertEqual(UserDefaults.standard.string(forKey: Localization.storageKey), AppLanguage.arabic.rawValue)
    }

    func testRemainingTimeUsesArabicUnits() {
        Localization.shared.language = .english
        XCTAssertEqual(Format.remaining(3660), "1h 01m")
        XCTAssertEqual(Format.remaining(600), "10m")

        Localization.shared.language = .arabic
        XCTAssertEqual(Format.remaining(3660), "1س 01د")
        XCTAssertEqual(Format.remaining(600), "10د")
    }

    /// Explicit UI copy requested for the Arabic interface.
    func testArabicQuitLabel() {
        Localization.shared.language = .arabic
        XCTAssertEqual(Localization.shared.string("settings.quit"), "إغلاق التطبيق")
    }

    /// The pre-multitheme "compact" style (icon + countdown) maps to
    /// `countdown` so existing users keep a live readout after upgrade.
    func testCompactThemeMigratesToCountdown() {
        XCTAssertEqual(TitleStyle.migrate("compact"), .countdown)
        XCTAssertEqual(TitleStyle.migrate("labeled"), .labeled)
        XCTAssertNil(TitleStyle.migrate("bogus"))

        UserDefaults.standard.set("compact", forKey: "miqat.titleStyle")
        let store = PrayerScheduleStore()
        XCTAssertEqual(store.titleStyle, .countdown)
    }
}
