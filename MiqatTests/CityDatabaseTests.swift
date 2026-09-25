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

    // MARK: - Arabic & country search

    func testSearchFindsArabicNames() {
        XCTAssertEqual(CityDatabase.search("الدار البيضاء").first?.name, "Casablanca")
        XCTAssertEqual(CityDatabase.search("دمشق").first?.name, "Damascus")
    }

    /// Hamza, ta marbuta, harakat and a missing article must not matter:
    /// "مكه" finds "مكة المكرمة", "رباط" finds "الرباط".
    func testArabicSearchIgnoresSpellingVariants() {
        XCTAssertEqual(CityDatabase.search("مكه").first?.country, "SA")
        XCTAssertEqual(CityDatabase.search("مَكَّة").first?.country, "SA")
        XCTAssertTrue(CityDatabase.search("رباط").contains { $0.name == "Rabat" })
        XCTAssertTrue(CityDatabase.search("اسطنبول").contains { $0.name == "Istanbul" })
    }

    func testSearchByCountryListsItsLargestCities() {
        for query in ["Syria", "سوريا"] {
            let results = CityDatabase.search(query)
            XCTAssertFalse(results.isEmpty, query)
            XCTAssertTrue(results.prefix(5).allSatisfy { $0.country == "SY" }, "\(query): \(results.prefix(5).map(\.name))")
        }
        // A city starting with the query still comes first; the country's
        // cities follow.
        XCTAssertEqual(CityDatabase.search("syr").map(\.name).prefix(3), ["Syracuse", "Aleppo", "Damascus"])
        XCTAssertEqual(CityDatabase.search("المغرب").first?.country, "MA")
        XCTAssertEqual(CityDatabase.search("UAE").first?.country, "AE")
    }

    /// Tripoli exists in Libya and Lebanon — a country narrows it.
    func testCityCommaCountryNarrowsResults() {
        XCTAssertEqual(CityDatabase.search("Tripoli, Lebanon").first?.country, "LB")
        XCTAssertEqual(CityDatabase.search("Tripoli, Libya").first?.country, "LY")
        XCTAssertEqual(CityDatabase.search("طرابلس، لبنان").first?.country, "LB")
        XCTAssertEqual(CityDatabase.search("tripoli lebanon").first?.country, "LB",
                       "trailing words match a country even without a comma")
    }

    func testCityNamesFollowUILanguage() {
        let rabat = CityDatabase.search("rabat").first!
        Localization.shared.language = .arabic
        XCTAssertEqual(rabat.localizedName, "الرباط")
        XCTAssertEqual(rabat.displayName, "الرباط، \(CountryName.arabic("MA"))")
        Localization.shared.language = .english
        XCTAssertEqual(rabat.displayName, "Rabat, \(CountryName.english("MA"))")
        Localization.shared.language = .system
    }

    func testPlaceFromCityIsBilingual() {
        let place = CityDatabase.place(from: CityDatabase.search("damascus").first!)
        XCTAssertEqual(place.source, .city)
        XCTAssertEqual(place.name, "Damascus, \(CountryName.english("SY"))")
        XCTAssertEqual(place.arabicName, "دمشق، \(CountryName.arabic("SY"))")
    }

    func testCoordinateParsing() {
        XCTAssertEqual(LocationChooser.parseCoordinate("33.51", positive: "N", negative: "S"), 33.51)
        XCTAssertEqual(LocationChooser.parseCoordinate("33,51", positive: "N", negative: "S"), 33.51)
        XCTAssertEqual(LocationChooser.parseCoordinate("7.6°W", positive: "E", negative: "W"), -7.6)
        XCTAssertEqual(LocationChooser.parseCoordinate(" 33.5 n ", positive: "N", negative: "S"), 33.5)
        XCTAssertNil(LocationChooser.parseCoordinate("abc", positive: "N", negative: "S"))
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
        XCTAssertEqual(place.name, "Near Istanbul, \(CountryName.english("TR"))")
        XCTAssertEqual(place.arabicName, "قرب اسطنبول، \(CountryName.arabic("TR"))")
        XCTAssertEqual(place.source, .coordinates)
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
        XCTAssertEqual(place.source, .detected)
    }
}
