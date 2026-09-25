import AppKit
import Combine
import Foundation

/// Owns settings, computes the daily schedule, and drives the live countdown.
final class PrayerScheduleStore: ObservableObject {

    // MARK: - Settings (persisted)

    @Published var place: Place? {
        didSet {
            guard oldValue != place else { return }
            if let place, let value = place.persistedValue {
                UserDefaults.standard.set(value, forKey: Keys.place)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.place)
            }
            invalidateSchedule()
        }
    }

    /// nil while the method follows the selected location's country — see `method`.
    @Published private(set) var methodOverride: CalculationMethodChoice? {
        didSet {
            guard oldValue != methodOverride else { return }
            if let methodOverride {
                UserDefaults.standard.set(methodOverride.rawValue, forKey: Keys.method)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.method)
            }
            invalidateSchedule()
        }
    }

    /// The method times are computed with: the user's explicit pick
    /// (`methodOverride`), or the convention of the current country.
    var method: CalculationMethodChoice {
        methodOverride ?? .defaultMethod(forCountryCode: place?.countryCode)
    }

    /// Sets the calculation method. Pass nil to go back to following the
    /// location's country convention ("Automatic" in Settings).
    func selectMethod(_ choice: CalculationMethodChoice?) {
        methodOverride = choice
    }

    @Published var madhab: AsrMadhab = .shafi {
        didSet {
            guard oldValue != madhab else { return }
            UserDefaults.standard.set(madhab.rawValue, forKey: Keys.madhab)
            invalidateSchedule()
        }
    }

    @Published var titleStyle: TitleStyle = .labeled {
        didSet {
            guard oldValue != titleStyle else { return }
            UserDefaults.standard.set(titleStyle.rawValue, forKey: Keys.titleStyle)
        }
    }

    /// Manual Hijri calendar offset in days (-2 ... +2) to match local moon sighting.
    @Published var hijriOffset: Int = 0 {
        didSet {
            guard oldValue != hijriOffset else { return }
            UserDefaults.standard.set(hijriOffset, forKey: Keys.hijriOffset)
        }
    }

    /// Master switch for adhan notifications (sound + banner).
    @Published var adhanEnabled: Bool = true {
        didSet {
            guard oldValue != adhanEnabled else { return }
            UserDefaults.standard.set(adhanEnabled, forKey: Keys.adhanEnabled)
        }
    }

    /// Prayers that trigger the adhan. Sunrise (Shuruq) is never included.
    @Published var adhanPrayers: Set<PrayerKey> = AdhanDefaults.enabledPrayers {
        didSet {
            guard oldValue != adhanPrayers else { return }
            UserDefaults.standard.set(
                adhanPrayers.map(\.rawValue).sorted(),
                forKey: Keys.adhanPrayers
            )
        }
    }

    /// Selected track per prayer; missing entries resolve to catalog defaults.
    @Published var adhanTracks: [PrayerKey: String] = [:] {
        didSet {
            guard oldValue != adhanTracks else { return }
            let raw = Dictionary(
                uniqueKeysWithValues: adhanTracks.map { ($0.key.rawValue, $0.value) }
            )
            UserDefaults.standard.set(raw, forKey: Keys.adhanTracks)
        }
    }

    /// The track a prayer would play right now (stored choice or default).
    func adhanTrack(for prayer: PrayerKey) -> AdhanTrack {
        if let id = adhanTracks[prayer], let track = AdhanCatalog.track(id: id),
           AdhanCatalog.tracks(for: prayer).contains(track) {
            return track
        }
        return AdhanCatalog.defaultTrack(for: prayer)
    }

    /// Whether a prayer entry should fire an adhan when its time arrives.
    func isAdhanEnabled(_ prayer: PrayerKey) -> Bool {
        adhanEnabled && prayer != .sunrise && adhanPrayers.contains(prayer)
    }

    /// Master switch for time-end reminders — opt-in, off out of the box.
    @Published var remindersEnabled: Bool = false {
        didSet {
            guard oldValue != remindersEnabled else { return }
            UserDefaults.standard.set(remindersEnabled, forKey: Keys.remindersEnabled)
        }
    }

    /// Minutes before a prayer's window closes that its reminder fires.
    @Published var reminderLeadMinutes: Int = ReminderDefaults.leadMinutes {
        didSet {
            guard oldValue != reminderLeadMinutes else { return }
            UserDefaults.standard.set(reminderLeadMinutes, forKey: Keys.reminderLead)
        }
    }

    /// Prayers whose window-end carries a reminder. Sunrise (Shuruq) is
    /// never included — it closes Fajr's window and has no reminder of its own.
    @Published var reminderPrayers: Set<PrayerKey> = ReminderDefaults.enabledPrayers {
        didSet {
            guard oldValue != reminderPrayers else { return }
            UserDefaults.standard.set(
                reminderPrayers.map(\.rawValue).sorted(),
                forKey: Keys.reminderPrayers
            )
        }
    }

    /// Independent switch for the Duha reminder — a separate feature with a
    /// fixed 20-minute lead before Dhuhr, unaffected by the master switch.
    @Published var duhaReminderEnabled: Bool = false {
        didSet {
            guard oldValue != duhaReminderEnabled else { return }
            UserDefaults.standard.set(duhaReminderEnabled, forKey: Keys.duhaReminderEnabled)
        }
    }

    /// Whether a prayer's window-end should post a reminder notification.
    func isReminderEnabled(_ prayer: PrayerKey) -> Bool {
        remindersEnabled && prayer != .sunrise && reminderPrayers.contains(prayer)
    }

    // MARK: - Live state

    /// The instant countdowns are measured against; ticks every second.
    @Published private(set) var now = Date()

    /// Today's six times (at the place), in canonical order.
    @Published private(set) var today: [PrayerEntry] = []

    /// The next prayer — possibly tomorrow's Fajr once Isha has passed.
    @Published private(set) var next: PrayerEntry?

    /// Tomorrow's Fajr: closes tonight's Isha window and arms the pre-Fajr
    /// reminder. Published for the reminder scheduler.
    @Published private(set) var tomorrowFajr: PrayerEntry?

    /// The time zone times should be displayed in.
    var displayTimeZone: TimeZone { place?.timeZone ?? .current }

    /// The prayer that entered most recently (before `now`), or nil if before Fajr.
    var previousPrayer: PrayerEntry? {
        today.last(where: { $0.date <= now })
    }

    /// Progress through the interval until `next` (0.0 to 1.0).
    var nextPrayerProgress: Double {
        guard let next else { return 0 }
        let nextDate = next.date
        let prevDate: Date
        if let previous = previousPrayer {
            prevDate = previous.date
        } else {
            // Before today's Fajr: estimate interval from yesterday's Isha (~8 hours before Fajr)
            prevDate = nextDate.addingTimeInterval(-8 * 3600)
        }
        let total = nextDate.timeIntervalSince(prevDate)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(prevDate)
        return min(max(elapsed / total, 0.0), 1.0)
    }

    // MARK: - Private state

    private var todayEntries: [PrayerEntry] = []
    /// Ordinal day (at the place) the cached schedule was computed for.
    private var cachedDay: Int?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let place = "miqat.place"
        /// The user's method override; absent while following the location.
        static let method = "miqat.method"
        static let madhab = "miqat.madhab"
        static let titleStyle = "miqat.titleStyle"
        static let hijriOffset = "miqat.hijriOffset"
        static let adhanEnabled = "miqat.adhan.enabled"
        static let adhanPrayers = "miqat.adhan.prayers"
        static let adhanTracks = "miqat.adhan.tracks"
        static let remindersEnabled = "miqat.reminder.enabled"
        static let reminderLead = "miqat.reminder.lead"
        static let reminderPrayers = "miqat.reminder.prayers"
        static let duhaReminderEnabled = "miqat.reminder.duha"
    }

    private enum AdhanDefaults {
        /// On out of the box for the five prayers — never sunrise.
        static let enabledPrayers: Set<PrayerKey> = [.fajr, .dhuhr, .asr, .maghrib, .isha]
    }

    private enum ReminderDefaults {
        static let leadMinutes = 30
        static let leadRange: ClosedRange<Int> = 5...90
        /// The prayers reminded by default — never sunrise.
        static let enabledPrayers: Set<PrayerKey> = [.fajr, .dhuhr, .asr, .maghrib, .isha]
    }

    // MARK: - Lifecycle

    init() {
        if let stored = UserDefaults.standard.string(forKey: Keys.place),
           let restored = Place(persistedValue: stored) {
            place = restored
        }
        // The pre-override app only wrote this key when the user explicitly
        // changed the method, so any stored value is a deliberate choice —
        // restore it as the override rather than re-following the country.
        if let stored = UserDefaults.standard.string(forKey: Keys.method),
           let restored = CalculationMethodChoice(rawValue: stored) {
            methodOverride = restored
        }
        if let stored = UserDefaults.standard.string(forKey: Keys.madhab),
           let restored = AsrMadhab(rawValue: stored) {
            madhab = restored
        }
        if let stored = UserDefaults.standard.string(forKey: Keys.titleStyle),
           let restored = TitleStyle.migrate(stored) {
            titleStyle = restored
        }
        if UserDefaults.standard.object(forKey: Keys.hijriOffset) != nil {
            hijriOffset = UserDefaults.standard.integer(forKey: Keys.hijriOffset)
        }
        if UserDefaults.standard.object(forKey: Keys.adhanEnabled) != nil {
            adhanEnabled = UserDefaults.standard.bool(forKey: Keys.adhanEnabled)
        }
        if let stored = UserDefaults.standard.stringArray(forKey: Keys.adhanPrayers) {
            adhanPrayers = Set(
                stored.compactMap(PrayerKey.init(rawValue:))
                    .filter { $0 != .sunrise }
            )
            // An empty selection stored by hand would mute everything; treat
            // "no valid prayer" as the defaults.
            if adhanPrayers.isEmpty {
                adhanPrayers = AdhanDefaults.enabledPrayers
            }
        }
        if let stored = UserDefaults.standard.dictionary(forKey: Keys.adhanTracks) as? [String: String] {
            var restored: [PrayerKey: String] = [:]
            for (key, trackID) in stored {
                guard let prayer = PrayerKey(rawValue: key),
                      prayer != .sunrise,
                      AdhanCatalog.track(id: trackID) != nil else { continue }
                restored[prayer] = trackID
            }
            adhanTracks = restored
        }
        if UserDefaults.standard.object(forKey: Keys.remindersEnabled) != nil {
            remindersEnabled = UserDefaults.standard.bool(forKey: Keys.remindersEnabled)
        }
        if UserDefaults.standard.object(forKey: Keys.reminderLead) != nil {
            let stored = UserDefaults.standard.integer(forKey: Keys.reminderLead)
            reminderLeadMinutes = min(
                max(stored, ReminderDefaults.leadRange.lowerBound),
                ReminderDefaults.leadRange.upperBound
            )
        }
        if let stored = UserDefaults.standard.stringArray(forKey: Keys.reminderPrayers) {
            reminderPrayers = Set(
                stored.compactMap(PrayerKey.init(rawValue:))
                    .filter { $0 != .sunrise }
            )
            // An empty selection stored by hand would mute everything; treat
            // "no valid prayer" as the defaults.
            if reminderPrayers.isEmpty {
                reminderPrayers = ReminderDefaults.enabledPrayers
            }
        }
        if UserDefaults.standard.object(forKey: Keys.duhaReminderEnabled) != nil {
            duhaReminderEnabled = UserDefaults.standard.bool(forKey: Keys.duhaReminderEnabled)
        }

        tick()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }

        // Catch up immediately after the Mac wakes or the clock/time zone moves.
        let darwin = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.invalidateSchedule() },
            darwin.addObserver(
                forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main
            ) { [weak self] _ in self?.invalidateSchedule() },
            darwin.addObserver(
                forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main
            ) { [weak self] _ in self?.invalidateSchedule() },
        ]
    }

    deinit {
        timer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Ticking

    /// Forces a recompute on the next tick (settings changed, Mac woke, …).
    private func invalidateSchedule() {
        cachedDay = nil
        tick()
    }

    private func tick() {
        now = Date()

        guard let place else {
            todayEntries = []
            tomorrowFajr = nil
            today = []
            next = nil
            return
        }

        // The civil day is tracked in the *place's* time zone, so the schedule
        // rolls over at the location's midnight, not the Mac's.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0

        if day != cachedDay {
            cachedDay = day
            todayEntries = PrayerEngine.entries(on: now, place: place, method: method, madhab: madhab) ?? []
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                tomorrowFajr = PrayerEngine.entries(on: tomorrow, place: place, method: method, madhab: madhab)?.first
            } else {
                tomorrowFajr = nil
            }
        }

        today = todayEntries
        next = todayEntries.first(where: { $0.date > now }) ?? tomorrowFajr
    }
}
