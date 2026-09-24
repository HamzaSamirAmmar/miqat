import XCTest
@testable import Miqat

/// Regression tests for place persistence.
///
/// The first location detection used to crash the app (SIGSEGV, see crash log
/// Miqat-2026-09-24-085829): `Place` conformed to both `Codable` and
/// `RawRepresentable`, so encoding dispatched to the RawRepresentable witness,
/// which asked for `rawValue`, which encoded `self` again — infinite recursion
/// until the stack guard page. These tests pin the persistence seam so a
/// reintroduced recursion fails loudly instead of shipping.
final class PlacePersistenceTests: XCTestCase {

    private let storageKey = "miqat.place"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    func testPlaceRoundTripsThroughPersistedValue() {
        let place = Place(
            name: "Casablanca, Morocco",
            latitude: 33.5731,
            longitude: -7.5898,
            timeZoneIdentifier: "Africa/Casablanca"
        )

        let stored = place.persistedValue
        XCTAssertNotNil(stored, "a valid place must encode")

        let restored = stored.flatMap(Place.init(persistedValue:))
        XCTAssertEqual(restored, place)
    }

    func testGarbagePersistedValueIsRejected() {
        XCTAssertNil(Place(persistedValue: "not json at all"))
        XCTAssertNil(Place(persistedValue: ""))
    }

    /// Setting a place on the store must persist it without crashing — the
    /// exact call chain the crash report showed (detect → didSet → encode).
    func testStorePersistsPlaceWhenSet() {
        let store = PrayerScheduleStore()
        let place = Place(
            name: "Makkah, Saudi Arabia",
            latitude: 21.427009,
            longitude: 39.828685,
            timeZoneIdentifier: "Asia/Riyadh"
        )

        store.place = place // ← used to overflow the stack here

        let stored = UserDefaults.standard.string(forKey: storageKey)
        XCTAssertNotNil(stored, "detected place must be persisted")
        XCTAssertEqual(stored.flatMap(Place.init(persistedValue:)), place)
    }

    func testStoreRestoresPersistedPlaceOnInit() {
        let place = Place(
            name: "Istanbul, Türkiye",
            latitude: 41.0082,
            longitude: 28.9784,
            timeZoneIdentifier: "Europe/Istanbul"
        )
        UserDefaults.standard.set(place.persistedValue!, forKey: storageKey)

        let store = PrayerScheduleStore()

        XCTAssertEqual(store.place, place)
        XCTAssertFalse(store.today.isEmpty, "restoring a place should immediately produce a schedule")
    }
}
