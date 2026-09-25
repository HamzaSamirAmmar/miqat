import XCTest
@testable import Miqat

// MARK: - Settings

final class ReminderSettingsTests: XCTestCase {

    private var defaults: UserDefaults { .standard }

    override func setUp() {
        super.setUp()
        removeReminderKeys()
    }

    override func tearDown() {
        removeReminderKeys()
        super.tearDown()
    }

    private func removeReminderKeys() {
        for key in [
            "miqat.reminder.enabled",
            "miqat.reminder.lead",
            "miqat.reminder.prayers",
            "miqat.reminder.duha",
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    func testFeatureIsOffByDefault() {
        let store = PrayerScheduleStore()

        XCTAssertFalse(store.remindersEnabled, "reminders are opt-in")
        XCTAssertFalse(store.duhaReminderEnabled, "Duha is a separate opt-in feature")
        XCTAssertEqual(store.reminderLeadMinutes, 30)
        XCTAssertEqual(store.reminderPrayers, [.fajr, .dhuhr, .asr, .maghrib, .isha])

        XCTAssertFalse(store.isReminderEnabled(.fajr), "master switch gates everything")
        XCTAssertFalse(store.isReminderEnabled(.sunrise), "sunrise carries no reminder")
    }

    func testPerPrayerGate() {
        let store = PrayerScheduleStore()
        store.remindersEnabled = true
        store.reminderPrayers = [.fajr]

        XCTAssertTrue(store.isReminderEnabled(.fajr))
        XCTAssertFalse(store.isReminderEnabled(.isha))

        store.remindersEnabled = false
        XCTAssertFalse(store.isReminderEnabled(.fajr), "master off mutes every prayer")
    }

    func testSettingsPersistAcrossStoreInstances() {
        let store = PrayerScheduleStore()
        store.remindersEnabled = true
        store.reminderLeadMinutes = 45
        store.reminderPrayers = [.maghrib]
        store.duhaReminderEnabled = true

        let restored = PrayerScheduleStore()
        XCTAssertTrue(restored.remindersEnabled)
        XCTAssertEqual(restored.reminderLeadMinutes, 45)
        XCTAssertEqual(restored.reminderPrayers, [.maghrib])
        XCTAssertTrue(restored.duhaReminderEnabled)
    }

    func testStoredLeadIsClampedToSupportedRange() {
        defaults.set(200, forKey: "miqat.reminder.lead")
        var store = PrayerScheduleStore()
        XCTAssertEqual(store.reminderLeadMinutes, 90)

        defaults.set(1, forKey: "miqat.reminder.lead")
        store = PrayerScheduleStore()
        XCTAssertEqual(store.reminderLeadMinutes, 5)
    }

    func testStoredSunriseIsFiltered() {
        defaults.set(["fajr", "sunrise"], forKey: "miqat.reminder.prayers")

        let store = PrayerScheduleStore()
        XCTAssertEqual(store.reminderPrayers, [.fajr],
                       "sunrise is filtered out of the enabled set")
    }

    func testEmptyStoredPrayerListFallsBackToDefaults() {
        defaults.set([String](), forKey: "miqat.reminder.prayers")

        let store = PrayerScheduleStore()
        XCTAssertEqual(store.reminderPrayers, [.fajr, .dhuhr, .asr, .maghrib, .isha])
    }
}

// MARK: - Scheduler

private final class SpyReminderNotifier: ReminderNotifying {
    var authorizationRequested = false
    var postedTitles: [String] = []

    func requestAuthorization() { authorizationRequested = true }
    func postReminder(title: String, body: String) { postedTitles.append(title) }
}

final class ReminderSchedulerTests: XCTestCase {

    private var store: PrayerScheduleStore!
    private let lead: TimeInterval = 30 * 60

    override func setUp() {
        super.setUp()
        removeReminderKeys()
        store = PrayerScheduleStore()
    }

    override func tearDown() {
        removeReminderKeys()
        super.tearDown()
    }

    private func removeReminderKeys() {
        for key in [
            "miqat.reminder.enabled",
            "miqat.reminder.lead",
            "miqat.reminder.prayers",
            "miqat.reminder.duha",
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func makeScheduler() -> (ReminderScheduler, SpyReminderNotifier) {
        let notifier = SpyReminderNotifier()
        let scheduler = ReminderScheduler(store: store, notifier: notifier)
        return (scheduler, notifier)
    }

    /// A synthetic day: Fajr at `start`, remaining prayers spaced out.
    private func makeDay(_ start: Date) -> [PrayerEntry] {
        [
            PrayerEntry(key: .fajr, date: start),
            PrayerEntry(key: .sunrise, date: start.addingTimeInterval(1.25 * 3600)),
            PrayerEntry(key: .dhuhr, date: start.addingTimeInterval(6 * 3600)),
            PrayerEntry(key: .asr, date: start.addingTimeInterval(9.5 * 3600)),
            PrayerEntry(key: .maghrib, date: start.addingTimeInterval(13 * 3600)),
            PrayerEntry(key: .isha, date: start.addingTimeInterval(14.5 * 3600)),
        ]
    }

    // MARK: Pure anchor logic

    func testRemindersAreAnchoredToWindowClosers() {
        let start = Date(timeIntervalSinceNow: -3600)
        let day = makeDay(start)
        let tomorrowFajr = PrayerEntry(
            key: .fajr, date: start.addingTimeInterval(24 * 3600)
        )
        // Mid-morning: today's Fajr has passed, so Isha closes at tomorrow's.
        let now = start.addingTimeInterval(2 * 3600)

        let reminders = ReminderScheduler.reminders(
            today: day, tomorrowFajr: tomorrowFajr, now: now, lead: lead
        )
        let bySubject = Dictionary(
            uniqueKeysWithValues: reminders.map { ($0.subject.id, $0) }
        )

        // Fajr closes at Shuruq — not before Fajr itself.
        XCTAssertEqual(bySubject["fajr"]?.deadline, day[1].date)
        XCTAssertEqual(bySubject["fajr"]?.fireDate, day[1].date.addingTimeInterval(-lead))
        // Duha is fixed at 20 minutes before Dhuhr…
        XCTAssertEqual(bySubject["duha"]?.deadline, day[2].date)
        XCTAssertEqual(bySubject["duha"]?.fireDate, day[2].date.addingTimeInterval(-20 * 60))
        // …no matter the configured lead.
        let withLongLead = ReminderScheduler.reminders(
            today: day, tomorrowFajr: tomorrowFajr, now: now, lead: 60 * 60
        )
        let duhaLong = withLongLead.first { $0.subject == .duha }
        XCTAssertEqual(duhaLong?.fireDate, day[2].date.addingTimeInterval(-20 * 60))

        XCTAssertEqual(bySubject["dhuhr"]?.deadline, day[3].date)
        XCTAssertEqual(bySubject["dhuhr"]?.fireDate, day[3].date.addingTimeInterval(-lead))
        XCTAssertEqual(bySubject["asr"]?.deadline, day[4].date)
        XCTAssertEqual(bySubject["maghrib"]?.deadline, day[5].date)
        // Isha closes at the next day's Fajr.
        XCTAssertEqual(bySubject["isha"]?.deadline, tomorrowFajr.date)
        XCTAssertEqual(bySubject["isha"]?.fireDate, tomorrowFajr.date.addingTimeInterval(-lead))
        // Sunrise never gets a reminder of its own.
        XCTAssertNil(bySubject["sunrise"])
    }

    func testIshaAnchorsToTodaysFajrDuringSmallHours() {
        // 2 a.m.: the schedule has already rolled over, so "tomorrow's Fajr"
        // is the day *after* — the night's Isha reminder must use today's.
        let fajr = Date(timeIntervalSinceNow: 2.7 * 3600)
        let day = makeDay(fajr)
        let tomorrowFajr = PrayerEntry(key: .fajr, date: fajr.addingTimeInterval(24 * 3600))
        let now = fajr.addingTimeInterval(-2.7 * 3600)

        let reminders = ReminderScheduler.reminders(
            today: day, tomorrowFajr: tomorrowFajr, now: now, lead: lead
        )
        let isha = reminders.first { $0.subject == .prayer(.isha) }

        XCTAssertEqual(isha?.deadline, day[0].date,
                       "the night's Isha closes at today's Fajr")
    }

    func testLongLeadDoesNotFireBeforeWindowOpens() {
        // Fajr→Shuruq gap is 75 min; a 90-min lead would land before Fajr
        // even starts — it must be clamped to just after the window opens.
        let start = Date(timeIntervalSinceNow: -3600)
        let day = makeDay(start)

        let reminders = ReminderScheduler.reminders(
            today: day, tomorrowFajr: nil, now: start, lead: 90 * 60
        )
        let fajr = reminders.first { $0.subject == .prayer(.fajr) }

        XCTAssertEqual(fajr?.fireDate, day[0].date.addingTimeInterval(60))
    }

    func testMissingTomorrowFajrOmitsIshaReminder() {
        let start = Date(timeIntervalSinceNow: -3600)
        let day = makeDay(start)
        // Mid-day: today's Fajr has passed and tomorrow's is unavailable.
        let now = day[2].date

        let reminders = ReminderScheduler.reminders(
            today: day, tomorrowFajr: nil, now: now, lead: lead
        )
        XCTAssertFalse(reminders.contains { $0.subject == .prayer(.isha) })
    }

    // MARK: Pure trigger logic

    func testDueRemindersWithinGraceWindow() {
        let start = Date(timeIntervalSinceNow: -3600)
        let day = makeDay(start)
        // 10 seconds after Fajr's reminder instant (Shuruq − lead).
        let now = day[1].date.addingTimeInterval(-lead + 10)

        let due = ReminderScheduler.dueReminders(
            today: day, tomorrowFajr: nil, now: now, lead: lead, alreadyFired: []
        ) { _ in true }
        XCTAssertTrue(due.contains { $0.subject == .prayer(.fajr) })
    }

    func testFutureRemindersDoNotFire() {
        let start = Date(timeIntervalSinceNow: -3600)
        let day = makeDay(start)
        // A minute before Fajr's reminder instant.
        let now = day[1].date.addingTimeInterval(-lead - 60)

        let due = ReminderScheduler.dueReminders(
            today: day, tomorrowFajr: nil, now: now, lead: lead, alreadyFired: []
        ) { _ in true }
        XCTAssertTrue(due.isEmpty)
    }

    func testRemindersBeyondGraceWindowDoNotFire() {
        let start = Date(timeIntervalSinceNow: -3600)
        let day = makeDay(start)
        // A Mac that slept through the reminder must not post it late.
        let now = day[1].date.addingTimeInterval(-lead + 91)

        let due = ReminderScheduler.dueReminders(
            today: day, tomorrowFajr: nil, now: now, lead: lead, alreadyFired: []
        ) { _ in true }
        XCTAssertTrue(due.isEmpty)
    }

    func testAlreadyFiredRemindersDoNotFireAgain() {
        let start = Date(timeIntervalSinceNow: -3600)
        let day = makeDay(start)
        let now = day[1].date.addingTimeInterval(-lead + 10)

        let reminders = ReminderScheduler.reminders(
            today: day, tomorrowFajr: nil, now: now, lead: lead
        )
        let fajr = reminders.first { $0.subject == .prayer(.fajr) }!

        let due = ReminderScheduler.dueReminders(
            today: day, tomorrowFajr: nil, now: now, lead: lead,
            alreadyFired: [fajr.id]
        ) { _ in true }
        XCTAssertFalse(due.contains { $0.subject == .prayer(.fajr) })
    }

    func testDisabledRemindersDoNotFire() {
        let start = Date(timeIntervalSinceNow: -3600)
        let day = makeDay(start)
        let now = day[1].date.addingTimeInterval(-lead + 10)

        let due = ReminderScheduler.dueReminders(
            today: day, tomorrowFajr: nil, now: now, lead: lead, alreadyFired: []
        ) { _ in false }
        XCTAssertTrue(due.isEmpty)
    }

    // MARK: End-to-end firing through the scheduler

    func testFiresOncePerDeadline() {
        store.remindersEnabled = true
        let (scheduler, notifier) = makeScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -3600))

        let fireAt = day[1].date.addingTimeInterval(-lead + 5)
        scheduler.process(today: day, tomorrowFajr: nil, now: fireAt)
        scheduler.process(today: day, tomorrowFajr: nil, now: fireAt.addingTimeInterval(5))

        XCTAssertEqual(notifier.postedTitles.count, 1, "must fire exactly once")
    }

    func testMasterOffPreventsFiring() {
        store.remindersEnabled = false
        let (scheduler, notifier) = makeScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -3600))

        scheduler.process(
            today: day, tomorrowFajr: nil,
            now: day[1].date.addingTimeInterval(-lead + 5)
        )
        XCTAssertTrue(notifier.postedTitles.isEmpty)
    }

    func testPerPrayerDisablePreventsFiring() {
        store.remindersEnabled = true
        store.reminderPrayers = [.fajr]
        let (scheduler, notifier) = makeScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -3600))

        // Dhuhr's reminder instant (Asr − lead).
        scheduler.process(
            today: day, tomorrowFajr: nil,
            now: day[3].date.addingTimeInterval(-lead + 5)
        )
        XCTAssertTrue(notifier.postedTitles.isEmpty, "Dhuhr was disabled")
    }

    func testDuhaFiresIndependentlyOfMaster() {
        store.remindersEnabled = false
        store.duhaReminderEnabled = true
        let (scheduler, notifier) = makeScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -3600))

        scheduler.process(
            today: day, tomorrowFajr: nil,
            now: day[2].date.addingTimeInterval(-20 * 60 + 5)
        )
        XCTAssertEqual(notifier.postedTitles.count, 1,
                       "Duha is a separate feature, not gated by the master switch")
    }

    func testDuhaOffByDefaultDoesNotFire() {
        store.remindersEnabled = true
        let (scheduler, notifier) = makeScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -3600))

        scheduler.process(
            today: day, tomorrowFajr: nil,
            now: day[2].date.addingTimeInterval(-20 * 60 + 5)
        )
        XCTAssertTrue(notifier.postedTitles.isEmpty)
    }

    func testSleepingThroughGraceWindowIsSkipped() {
        store.remindersEnabled = true
        let (scheduler, notifier) = makeScheduler()
        let day = makeDay(Date(timeIntervalSinceNow: -3600))

        // Woke an hour after the reminder instant — skip it.
        scheduler.process(
            today: day, tomorrowFajr: nil,
            now: day[1].date.addingTimeInterval(-lead + 3600)
        )
        XCTAssertTrue(notifier.postedTitles.isEmpty)
    }

    func testNextDayReFires() {
        store.remindersEnabled = true
        let (scheduler, notifier) = makeScheduler()
        let today = makeDay(Date(timeIntervalSinceNow: -10))
        let tomorrow = makeDay(today[0].date.addingTimeInterval(86_400))

        scheduler.process(today: today, tomorrowFajr: nil,
                          now: today[1].date.addingTimeInterval(-lead + 5))
        XCTAssertEqual(notifier.postedTitles.count, 1)

        scheduler.process(today: tomorrow, tomorrowFajr: nil,
                          now: tomorrow[1].date.addingTimeInterval(-lead + 5))
        XCTAssertEqual(notifier.postedTitles.count, 2,
                       "the next day's deadline must fire again")
    }

    // MARK: Copy

    func testMinutesPhrasePluralAgreement() {
        Localization.shared.language = .arabic
        XCTAssertEqual(ReminderScheduler.minutesPhrase(20), "20 دقيقة")
        XCTAssertEqual(ReminderScheduler.minutesPhrase(10), "10 دقائق")

        Localization.shared.language = .english
        XCTAssertEqual(ReminderScheduler.minutesPhrase(30), "30 min")
    }
}
