import XCTest
@testable import Miqat

final class CityDatabaseTests: XCTestCase {

    // MARK: - Loading

    func testDatabaseBundlesCities() {
        XCTAssertGreaterThan(CityDatabase.cities.count, 10_000,
                             "bundled database should contain ~12k cities")
        XCTAssertTrue(CityDatabase.cities.contains { $0.name == "Casablanca" && $0.country == "MA" })
    }

    // MARK: - Search

    func testSearchByPrefixRanksBiggestCityFirst() {
        let results = CityDatabase.search("casa")
        XCTAssertEqual(results.first?.name, "Casablanca")
        XCTAssertEqual(results.first?.country, "MA")
    }

    /// GeoNames stores "Tétouan" — typing plain ASCII must still find it.
    func testSearchIsDiacriticInsensitive() {
        let results = CityDatabase.search("tetouan")
        XCTAssertTrue(results.contains { $0.name == "Tétouan" && $0.country == "MA" })
    }

    func testSearchRequiresTwoCharacters() {
        XCTAssertTrue(CityDatabase.search("f").isEmpty)
        XCTAssertTrue(CityDatabase.search("  ").isEmpty)
    }

    // MARK: - Nearest city

    func testNearestCity() {
        // Central Casablanca coordinates → Casablanca itself.
        let nearest = CityDatabase.nearest(toLatitude: 33.58831, longitude: -7.61138)
        XCTAssertEqual(nearest?.name, "Casablanca")
        XCTAssertEqual(nearest?.country, "MA")
    }

    /// GeoNames lists Istanbul districts separately (e.g. Eminönü); the true
    /// nearest is the district, but labeling should prefer the metropolis.
    func testNearestNotablePrefersLargerNearbyCity() {
        let coordinates = (latitude: 41.0082, longitude: 28.9784) // Istanbul historic center

        XCTAssertEqual(CityDatabase.nearest(toLatitude: coordinates.latitude, longitude: coordinates.longitude)?.name,
                       "Eminönü", "true nearest is the district itself")
        XCTAssertEqual(CityDatabase.nearestNotable(toLatitude: coordinates.latitude, longitude: coordinates.longitude)?.name,
                       "Istanbul", "notable nearest should be the biggest city in the window")
    }

    // MARK: - Manual coordinates (fully offline place construction)

    func testCountryFlagEmoji() {
        XCTAssertEqual(CountryFlag.emoji(for: "MA"), "🇲🇦")
        XCTAssertEqual(CountryFlag.emoji(for: "US"), "🇺🇸")
        XCTAssertEqual(CountryFlag.emoji(for: nil), "📍")
        XCTAssertEqual(CountryFlag.emoji(for: "USA"), "📍")
        XCTAssertEqual(CountryFlag.emoji(for: "ma"), "📍", "non-uppercase input falls back")
    }

    func testPlaceFromCityCarriesCountryCode() {
        let casablanca = CityDatabase.search("casablanca").first!
        XCTAssertEqual(casablanca.flagEmoji, "🇲🇦")
        XCTAssertEqual(CityDatabase.place(from: casablanca).countryCode, "MA")
    }

    func testManualPlaceUsesNearestCityTimeZoneAndLabel() {
        // Istanbul coordinates, on a Mac set to any system timezone.
        let place = CityDatabase.manualPlace(name: nil, latitude: 41.0082, longitude: 28.9784)
        XCTAssertEqual(place.timeZoneIdentifier, "Europe/Istanbul")
        XCTAssertEqual(place.name, "Near Istanbul, TR")
    }

    func testManualPlaceRespectsCustomName() {
        let place = CityDatabase.manualPlace(name: "Dar", latitude: 33.57, longitude: -7.59)
        XCTAssertEqual(place.name, "Dar")
        XCTAssertEqual(place.timeZoneIdentifier, "Africa/Casablanca",
                       "nearest city (Casablanca) should supply the timezone, not the system default")
    }

    func testNearestCityPlaceKeepsDetectedCoordinates() {
        let place = CityDatabase.nearestCityPlace(latitude: 33.52, longitude: -7.05)
        XCTAssertEqual(place.latitude, 33.52, accuracy: 0.000001)
        XCTAssertEqual(place.longitude, -7.05, accuracy: 0.000001)
        XCTAssertNotNil(TimeZone(identifier: place.timeZoneIdentifier),
                        "nearest city must supply a valid timezone")
    }
}
