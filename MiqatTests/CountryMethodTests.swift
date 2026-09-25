import XCTest
@testable import Miqat

/// The country → default calculation-method table behind "Automatic".
final class CountryMethodTests: XCTestCase {

    private let placeKey = "miqat.place"
    private let methodKey = "miqat.method"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: placeKey)
        UserDefaults.standard.removeObject(forKey: methodKey)
        super.tearDown()
    }

    // MARK: - Table

    func testKnownCountryDefaults() {
        let expectations: [String: CalculationMethodChoice] = [
            // Arabian Peninsula
            "SA": .ummAlQura,
            "AE": .dubai,
            "QA": .qatar,
            "KW": .kuwait,
            // Egyptian authority and its neighbours
            "EG": .egyptian,
            "SD": .egyptian,
            "LY": .egyptian,
            "SO": .egyptian,
            // South Asia
            "PK": .karachi,
            "IN": .karachi,
            "BD": .karachi,
            "AF": .karachi,
            "LK": .karachi,
            // MUIS / JAKIM / Kemenag share adhan's Singapore angles
            "SG": .singapore,
            "MY": .singapore,
            "ID": .singapore,
            "BN": .singapore,
            // State-specific authorities
            "TR": .turkey,
            "IR": .tehran,
            "US": .northAmerica,
            "CA": .northAmerica,
        ]

        for (code, method) in expectations {
            XCTAssertEqual(
                CalculationMethodChoice.defaultMethod(forCountryCode: code), method,
                "\(code) should default to \(method.rawValue)"
            )
        }
    }

    /// The Levant, Europe and most of the world follow Muslim World League —
    /// via the fallback, so the table stays small.
    func testUnlistedCountriesFallBackToMuslimWorldLeague() {
        for code in ["SY", "JO", "LB", "PS", "IQ", "YE", "OM", "BH",
                     "MA", "DZ", "TN", "GB", "FR", "DE", "RU", "CN", "AU"] {
            XCTAssertEqual(CalculationMethodChoice.defaultMethod(forCountryCode: code), .muslimWorldLeague)
        }
    }

    func testNilUnknownAndLowercaseCountryCodes() {
        XCTAssertEqual(CalculationMethodChoice.defaultMethod(forCountryCode: nil), .muslimWorldLeague)
        XCTAssertEqual(CalculationMethodChoice.defaultMethod(forCountryCode: ""), .muslimWorldLeague)
        XCTAssertEqual(CalculationMethodChoice.defaultMethod(forCountryCode: "XX"), .muslimWorldLeague)
        // CoreLocation and the city database both deliver uppercase ISO
        // codes, but a lowercase code must still resolve.
        XCTAssertEqual(CalculationMethodChoice.defaultMethod(forCountryCode: "sa"), .ummAlQura)
    }

    // MARK: - Store behaviour

    private func place(countryCode: String?) -> Place {
        Place(
            name: "Test City",
            latitude: 21.427009,
            longitude: 39.828685,
            timeZoneIdentifier: "Asia/Riyadh",
            countryCode: countryCode
        )
    }

    /// With no stored preference the method follows the selected country,
    /// and re-selecting a place re-resolves it.
    func testMethodFollowsCountryUntilOverridden() {
        let store = PrayerScheduleStore()
        XCTAssertNil(store.methodOverride, "fresh installs start on Automatic")

        store.place = place(countryCode: "SA")
        XCTAssertEqual(store.method, .ummAlQura)
        XCTAssertNil(UserDefaults.standard.string(forKey: methodKey),
                     "Automatic must not persist an override")

        store.place = place(countryCode: "TR")
        XCTAssertEqual(store.method, .turkey)

        // Back to a Muslim World League country — still Automatic.
        store.place = place(countryCode: "SY")
        XCTAssertEqual(store.method, .muslimWorldLeague)
    }

    /// One explicit pick wins over the country and survives restarts.
    func testExplicitOverrideBeatsCountryAndPersists() {
        let store = PrayerScheduleStore()
        store.place = place(countryCode: "SA")
        XCTAssertEqual(store.method, .ummAlQura)

        store.selectMethod(.karachi)
        XCTAssertEqual(store.method, .karachi)
        XCTAssertEqual(UserDefaults.standard.string(forKey: methodKey), "karachi")

        // Moving to another country leaves the override alone.
        store.place = place(countryCode: "TR")
        XCTAssertEqual(store.method, .karachi)

        let restored = PrayerScheduleStore()
        XCTAssertEqual(restored.methodOverride, .karachi)
        restored.place = place(countryCode: "SA")
        XCTAssertEqual(restored.method, .karachi)
    }

    /// Re-choosing Automatic clears the stored override and re-follows the country.
    func testSelectingNilReturnsToCountryDefault() {
        let store = PrayerScheduleStore()
        store.place = place(countryCode: "EG")
        store.selectMethod(.karachi)

        store.selectMethod(nil)

        XCTAssertNil(store.methodOverride)
        XCTAssertNil(UserDefaults.standard.string(forKey: methodKey))
        XCTAssertEqual(store.method, .egyptian)
    }

    /// Users upgrading from 1.x only have this key set when they explicitly
    /// changed the method back then — keep honouring that choice.
    func testLegacyStoredMethodBecomesOverride() {
        UserDefaults.standard.set("egyptian", forKey: methodKey)
        let store = PrayerScheduleStore()
        store.place = place(countryCode: "SA")

        XCTAssertEqual(store.methodOverride, .egyptian)
        XCTAssertEqual(store.method, .egyptian)
    }
}
