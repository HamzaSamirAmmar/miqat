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

    @Published var method: CalculationMethodChoice = .muslimWorldLeague {
        didSet {
            guard oldValue != method else { return }
            UserDefaults.standard.set(method.rawValue, forKey: Keys.method)
            invalidateSchedule()
        }
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

    // MARK: - Live state

    /// The instant countdowns are measured against; ticks every second.
    @Published private(set) var now = Date()

    /// Today's six times (at the place), in canonical order.
    @Published private(set) var today: [PrayerEntry] = []

    /// The next prayer — possibly tomorrow's Fajr once Isha has passed.
    @Published private(set) var next: PrayerEntry?

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
    private var tomorrowFajr: PrayerEntry?
    /// Ordinal day (at the place) the cached schedule was computed for.
    private var cachedDay: Int?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let place = "miqat.place"
        static let method = "miqat.method"
        static let madhab = "miqat.madhab"
        static let titleStyle = "miqat.titleStyle"
        static let hijriOffset = "miqat.hijriOffset"
    }

    // MARK: - Lifecycle

    init() {
        if let stored = UserDefaults.standard.string(forKey: Keys.place),
           let restored = Place(persistedValue: stored) {
            place = restored
        }
        if let stored = UserDefaults.standard.string(forKey: Keys.method),
           let restored = CalculationMethodChoice(rawValue: stored) {
            method = restored
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
