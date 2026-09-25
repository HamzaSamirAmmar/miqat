import XCTest
@testable import Miqat

// MARK: - Catalog

final class AdhanCatalogTests: XCTestCase {

    func testEveryTrackResolvesToBundledFile() {
        for track in AdhanCatalog.tracks {
            let url = AdhanCatalog.url(for: track)
            XCTAssertNotNil(url, "missing bundled file for track \(track.id)")
            if let url {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                              "bundle URL points nowhere for \(track.id)")
            }
        }
    }

    func testTrackIdsAreUnique() {
        let ids = AdhanCatalog.tracks.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testFajrAndStandardSplit() {
        XCTAssertEqual(AdhanCatalog.fajrTracks.count, 3)
        XCTAssertEqual(AdhanCatalog.standardTracks.count, 7)
        XCTAssertTrue(AdhanCatalog.fajrTracks.allSatisfy(\.isFajrVariant))
        XCTAssertTrue(AdhanCatalog.standardTracks.allSatisfy { !$0.isFajrVariant })
    }

    func testDefaultTracks() {
        XCTAssertTrue(AdhanCatalog.defaultTrack(for: .fajr).isFajrVariant,
                      "Fajr should default to a Fajr variant")
        for prayer in PrayerKey.allCases where prayer != .fajr {
            XCTAssertFalse(AdhanCatalog.defaultTrack(for: prayer).isFajrVariant,
                           "\(prayer.rawValue) should default to a standard adhan")
        }
    }

    /// Fajr only ever picks from its variants, other prayers from standard
    /// adhans — the families never mix in one picker.
    func testTracksOfferedPerPrayer() {
        XCTAssertEqual(AdhanCatalog.tracks(for: .fajr), AdhanCatalog.fajrTracks)
        for prayer in PrayerKey.allCases where prayer != .fajr {
            XCTAssertEqual(AdhanCatalog.tracks(for: prayer), AdhanCatalog.standardTracks)
        }
    }

    func testTrackDisplayNamesAreLocalized() {
        Localization.shared.language = .english
        for track in AdhanCatalog.tracks {
            XCTAssertNotEqual(track.displayName, "adhan.track.\(track.id)",
                              "missing localization for \(track.id)")
        }
    }
}

// MARK: - Settings

final class AdhanSettingsTests: XCTestCase {

    private var defaults: UserDefaults { .standard }

    override func setUp() {
        super.setUp()
        removeAdhanKeys()
    }

    override func tearDown() {
        removeAdhanKeys()
        super.tearDown()
    }

    private func removeAdhanKeys() {
        for key in ["miqat.adhan.enabled", "miqat.adhan.prayers", "miqat.adhan.tracks"] {
            defaults.removeObject(forKey: key)
        }
    }

    func testDefaultsAreOnForFivePrayers() {
        let store = PrayerScheduleStore()

        XCTAssertTrue(store.adhanEnabled)
        XCTAssertEqual(store.adhanPrayers, [.fajr, .dhuhr, .asr, .maghrib, .isha])
        XCTAssertFalse(store.adhanPrayers.contains(.sunrise))

        for prayer in PrayerKey.allCases where prayer != .sunrise {
            XCTAssertTrue(store.isAdhanEnabled(prayer))
        }
        XCTAssertFalse(store.isAdhanEnabled(.sunrise),
                       "sunrise must never fire an adhan")
    }

    func testGlobalToggleSilencesEverything() {
        let store = PrayerScheduleStore()
        store.adhanEnabled = false

        XCTAssertFalse(store.isAdhanEnabled(.fajr))
        XCTAssertFalse(store.isAdhanEnabled(.isha))
    }

    func testSettingsPersistAcrossStoreInstances() {
        let store = PrayerScheduleStore()
        store.adhanEnabled = false
        store.adhanPrayers = [.fajr, .maghrib]
        store.adhanTracks = [.fajr: "madinah-fajr", .maghrib: "aqsa"]

        let restored = PrayerScheduleStore()
        XCTAssertFalse(restored.adhanEnabled)
        XCTAssertEqual(restored.adhanPrayers, [.fajr, .maghrib])
        XCTAssertEqual(restored.adhanTracks[.fajr], "madinah-fajr")
        XCTAssertEqual(restored.adhanTracks[.maghrib], "aqsa")
    }

    func testUnstoredTrackFallsBackToDefault() {
        let store = PrayerScheduleStore()
        XCTAssertEqual(store.adhanTrack(for: .fajr).id, AdhanCatalog.defaultTrack(for: .fajr).id)
        XCTAssertEqual(store.adhanTrack(for: .isha).id, AdhanCatalog.defaultTrack(for: .isha).id)
    }

    func testStoredInvalidEntriesAreSanitized() {
        defaults.set(["fajr": "long-gone-track", "sunrise": "makkah"], forKey: "miqat.adhan.tracks")
        defaults.set(["fajr", "sunrise"], forKey: "miqat.adhan.prayers")

        let store = PrayerScheduleStore()

        XCTAssertNil(store.adhanTracks[.sunrise], "sunrise must not store a track")
        XCTAssertEqual(store.adhanTrack(for: .fajr).id,
                       AdhanCatalog.defaultTrack(for: .fajr).id,
                       "unknown track id falls back to the default")
        XCTAssertFalse(store.adhanPrayers.contains(.sunrise),
                       "sunrise is filtered out of the enabled set")
        XCTAssertEqual(store.adhanPrayers, [.fajr],
                       "valid stored prayers are kept as-is")
    }

    func testStoredFajrVariantOnOtherPrayerFallsBack() {
        let store = PrayerScheduleStore()
        store.adhanTracks = [.dhuhr: "makkah-fajr"]

        // The picker never offers this, but a hand-edited defaults entry
        // must resolve to something playable.
        XCTAssertEqual(store.adhanTrack(for: .dhuhr).id,
                       AdhanCatalog.defaultTrack(for: .dhuhr).id)
    }

    /// Stored before the pickers were split (a standard track chosen for
    /// Fajr) — must resolve to the Fajr default, not play a standard adhan.
    func testStoredStandardTrackOnFajrFallsBack() {
        let store = PrayerScheduleStore()
        store.adhanTracks = [.fajr: "alafasy"]

        XCTAssertEqual(store.adhanTrack(for: .fajr).id,
                       AdhanCatalog.defaultTrack(for: .fajr).id)
    }

    func testEmptyStoredPrayerListFallsBackToDefaults() {
        defaults.set([String](), forKey: "miqat.adhan.prayers")

        let store = PrayerScheduleStore()
        XCTAssertEqual(store.adhanPrayers, [.fajr, .dhuhr, .asr, .maghrib, .isha])
    }
}

// MARK: - Scheduler

private final class SpyPlayer: AdhanPlaying {
    var playedTrackIDs: [String] = []
    var stopCount = 0

    func play(trackID: String) { playedTrackIDs.append(trackID) }
    func stop() { stopCount += 1 }
}

private final class SpyNotifier: AdhanNotifying {
    var authorizationRequested = false
    var postedTitles: [String] = []

    func requestAuthorization() { authorizationRequested = true }
    func post(title: String, body: String) { postedTitles.append(title) }
}

final class AdhanSchedulerTests: XCTestCase {

    private var store: PrayerScheduleStore!

    override func setUp() {
        super.setUp()
        for key in ["miqat.adhan.enabled", "miqat.adhan.prayers", "miqat.adhan.tracks"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        store = PrayerScheduleStore()
    }

    override func tearDown() {
        for key in ["miqat.adhan.enabled", "miqat.adhan.prayers", "miqat.adhan.tracks"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    private func makePlayerNotifierScheduler() -> (AdhanScheduler, SpyPlayer, SpyNotifier) {
        let player = SpyPlayer()
        let notifier = SpyNotifier()
        let scheduler = AdhanScheduler(store: store, player: player, notifier: notifier)
        return (scheduler, player, notifier)
    }

    /// A synthetic day: Fajr at `start`, remaining prayers spaced out.
    private func makeDay(_ start: Date) -> [PrayerEntry] {
        [
            PrayerEntry(key: .fajr, date: start),
            PrayerEntry(key: .sunrise, date: start.addingTimeInterval(1 * 3600)),
            PrayerEntry(key: .dhuhr, date: start.addingTimeInterval(6 * 3600)),
            PrayerEntry(key: .asr, date: start.addingTimeInterval(9.5 * 3600)),
            PrayerEntry(key: .maghrib, date: start.addingTimeInterval(13 * 3600)),
            PrayerEntry(key: .isha, date: start.addingTimeInterval(14.5 * 3600)),
        ]
    }

    // MARK: Pure trigger logic

    func testDueEntriesWithinGraceWindow() {
        let entry = PrayerEntry(key: .fajr, date: Date(timeIntervalSinceNow: -89))

        let due = AdhanScheduler.dueEntries(in: [entry], now: Date(), alreadyFired: [], isEnabled: { _ in true })
        XCTAssertEqual(due.map(\.id), [entry.id])
    }

    func testFutureEntriesDoNotFire() {
        let entry = PrayerEntry(key: .fajr, date: Date(timeIntervalSinceNow: 60))

        let due = AdhanScheduler.dueEntries(in: [entry], now: Date(), alreadyFired: [], isEnabled: { _ in true })
        XCTAssertTrue(due.isEmpty)
    }

    func testEntriesBeyondGraceWindowDoNotFire() {
        // A Mac that slept through Fajr must not blast a belated adhan on wake.
        let entry = PrayerEntry(key: .fajr, date: Date(timeIntervalSinceNow: -91))

        let due = AdhanScheduler.dueEntries(in: [entry], now: Date(), alreadyFired: [], isEnabled: { _ in true })
        XCTAssertTrue(due.isEmpty)
    }

    func testAlreadyFiredEntriesDoNotFireAgain() {
        let entry = PrayerEntry(key: .fajr, date: Date(timeIntervalSinceNow: -10))

        let due = AdhanScheduler.dueEntries(in: [entry], now: Date(), alreadyFired: [entry.id], isEnabled: { _ in true })
        XCTAssertTrue(due.isEmpty)
    }

    func testDisabledEntriesDoNotFire() {
        let entry = PrayerEntry(key: .fajr, date: Date(timeIntervalSinceNow: -10))

        let due = AdhanScheduler.dueEntries(in: [entry], now: Date(), alreadyFired: [], isEnabled: { _ in false })
        XCTAssertTrue(due.isEmpty)
    }

    // MARK: End-to-end firing through the scheduler

    func testFiresOnceWithTrackAndBanner() {
        let (scheduler, player, notifier) = makePlayerNotifierScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -10))

        scheduler.process(day, now: day[0].date.addingTimeInterval(10))
        scheduler.process(day, now: day[0].date.addingTimeInterval(11))

        XCTAssertEqual(player.playedTrackIDs.count, 1, "must fire exactly once")
        XCTAssertEqual(player.playedTrackIDs[0], AdhanCatalog.defaultTrack(for: .fajr).id)
        XCTAssertEqual(notifier.postedTitles.count, 1)
    }

    func testSunriseNeverFires() {
        let (scheduler, player, _) = makePlayerNotifierScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -3600))

        // "Now" lands right on sunrise.
        let sunrise = day[1]
        scheduler.process(day, now: sunrise.date.addingTimeInterval(5))

        XCTAssertTrue(player.playedTrackIDs.isEmpty)
    }

    func testPerPrayerDisablePreventsFiring() {
        store.adhanPrayers = [.fajr]
        let (scheduler, player, _) = makePlayerNotifierScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -3600))

        scheduler.process(day, now: day[2].date.addingTimeInterval(5))

        XCTAssertTrue(player.playedTrackIDs.isEmpty, "Dhuhr was disabled")
    }

    func testGlobalDisablePreventsFiring() {
        store.adhanEnabled = false
        let (scheduler, player, notifier) = makePlayerNotifierScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -10))

        scheduler.process(day, now: day[0].date.addingTimeInterval(5))

        XCTAssertTrue(player.playedTrackIDs.isEmpty)
        XCTAssertTrue(notifier.postedTitles.isEmpty)
    }

    func testCustomTrackSelectionIsPlayed() {
        store.adhanTracks = [.fajr: "madinah-fajr"]
        let (scheduler, player, _) = makePlayerNotifierScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -10))

        scheduler.process(day, now: day[0].date.addingTimeInterval(5))

        XCTAssertEqual(player.playedTrackIDs, ["madinah-fajr"])
    }

    func testSleepingThroughGraceWindowIsSkipped() {
        let (scheduler, player, _) = makePlayerNotifierScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -3600))

        // Woke up an hour after Fajr — skip it.
        scheduler.process(day, now: day[0].date.addingTimeInterval(3600))

        XCTAssertTrue(player.playedTrackIDs.isEmpty)
    }

    func testDayRolloverReArmsFiring() {
        let (scheduler, player, _) = makePlayerNotifierScheduler()
        let today = makeDay(Date(timeIntervalSinceNow: -10))
        let tomorrow = makeDay(today[0].date.addingTimeInterval(86_400))

        scheduler.process(today, now: today[0].date.addingTimeInterval(10))
        XCTAssertEqual(player.playedTrackIDs.count, 1)

        scheduler.process(tomorrow, now: tomorrow[0].date.addingTimeInterval(10))
        XCTAssertEqual(player.playedTrackIDs.count, 2,
                       "next day's Fajr must fire again after rollover")
    }
}
