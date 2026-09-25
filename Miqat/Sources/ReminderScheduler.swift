import Combine
import Foundation

/// One time-end reminder: what it is about, when it fires, and the window
/// deadline it announces.
struct PrayerReminder: Equatable {

    /// The prayer whose window is closing. Duha is not a schedule row — it
    /// exists only as this reminder, fixed at 20 minutes before Dhuhr.
    enum Subject: Equatable {
        case prayer(PrayerKey)
        case duha

        var id: String {
            switch self {
            case .prayer(let key): return key.rawValue
            case .duha: return "duha"
            }
        }

        var displayName: String {
            switch self {
            case .prayer(let key): return key.displayName
            case .duha: return Localization.shared.string("prayer.duha")
            }
        }
    }

    let subject: Subject
    /// When the notification fires — the deadline minus the lead time.
    let fireDate: Date
    /// The instant the window closes (Shuruq for Fajr, the next Fajr for
    /// Isha, …).
    let deadline: Date

    /// Identity is anchored to the deadline, not the fire date: changing the
    /// lead must never re-fire an already-delivered reminder, and one
    /// deadline must never notify twice across day rollovers.
    var id: String {
        "reminder.\(subject.id).\(Int(deadline.timeIntervalSince1970))"
    }
}

/// Watches the store's clock and posts a notification before each enabled
/// prayer's window closes:
///
/// - Fajr closes at Shuruq (sunrise)
/// - Dhuhr at Asr · Asr at Maghrib · Maghrib at Isha · Isha at the next Fajr
/// - Duha — a separate toggle with a fixed lead — closes before Dhuhr
///
/// Unlike the adhan these are plain notifications with the default sound;
/// nothing is played, so no extra App Nap hold is needed beyond the one
/// `AdhanScheduler` already keeps for the process.
final class ReminderScheduler: ObservableObject {

    /// A reminder missed by more than this window does not fire — the same
    /// sleep-safety rule the adhan follows.
    static let graceWindow: TimeInterval = 90

    /// The Duha reminder's lead — deliberately not configurable.
    static let duhaLead: TimeInterval = 20 * 60

    private let store: PrayerScheduleStore
    private let notifier: ReminderNotifying
    private var cancellable: AnyCancellable?
    /// Fired reminders by id → deadline; pruned so the map stays tiny.
    private var firedDeadlines: [String: Date] = [:]

    init(store: PrayerScheduleStore, notifier: ReminderNotifying) {
        self.store = store
        self.notifier = notifier
    }

    func start() {
        notifier.requestAuthorization()

        cancellable = store.$now
            .receive(on: DispatchQueue.main)
            .sink { [weak self] now in
                guard let self else { return }
                self.process(
                    today: self.store.today,
                    tomorrowFajr: self.store.tomorrowFajr,
                    now: now
                )
            }
    }

    // MARK: - Firing

    /// Examines the schedule against `now`, posting anything due. Internal so
    /// tests can drive it with synthetic times and a spy notifier.
    func process(today: [PrayerEntry], tomorrowFajr: PrayerEntry?, now: Date) {
        let due = Self.dueReminders(
            today: today,
            tomorrowFajr: tomorrowFajr,
            now: now,
            lead: TimeInterval(store.reminderLeadMinutes * 60),
            alreadyFired: Set(firedDeadlines.keys)
        ) { [store] reminder in
            switch reminder.subject {
            case .prayer(let key): return store.isReminderEnabled(key)
            case .duha: return store.duhaReminderEnabled
            }
        }

        for reminder in due {
            firedDeadlines[reminder.id] = reminder.deadline
            fire(reminder)
        }

        // Ids are unique per deadline, so stale entries only ever consume
        // memory — drop everything older than a day.
        let cutoff = now.addingTimeInterval(-24 * 3600)
        firedDeadlines = firedDeadlines.filter { $0.value > cutoff }
    }

    private func fire(_ reminder: PrayerReminder) {
        let minutes = max(
            1,
            Int((reminder.deadline.timeIntervalSince(reminder.fireDate) / 60).rounded())
        )
        notifier.postReminder(
            title: Localization.shared.string(
                "reminder.notification.title",
                reminder.subject.displayName,
                Self.minutesPhrase(minutes)
            ),
            body: Localization.shared.string(
                "reminder.notification.deadline",
                Format.time(reminder.deadline, timeZone: store.displayTimeZone)
            )
        )
    }

    /// "30 min" / "30 دقيقة", with Arabic plural agreement.
    static func minutesPhrase(_ minutes: Int) -> String {
        if Localization.shared.isArabic {
            let unit = (3...10).contains(minutes) ? "دقائق" : "دقيقة"
            return "\(minutes) \(unit)"
        }
        return "\(minutes) min"
    }

    // MARK: - Pure logic

    /// Derives every reminder the schedule implies.
    ///
    /// The Isha reminder is anchored to the next Fajr *after `now`*: during
    /// the day that is tomorrow's Fajr, but in the small hours after the
    /// schedule has rolled over it is today's — otherwise the pre-Fajr
    /// reminder would vanish at midnight.
    static func reminders(
        today: [PrayerEntry],
        tomorrowFajr: PrayerEntry?,
        now: Date,
        lead: TimeInterval,
        duhaLead: TimeInterval = ReminderScheduler.duhaLead
    ) -> [PrayerReminder] {
        let byKey = Dictionary(uniqueKeysWithValues: today.map { ($0.key, $0) })
        guard !byKey.isEmpty else { return [] }

        /// (window, closing boundary): each prayer ends when the next arrives.
        let closers: [(prayer: PrayerKey, boundary: PrayerKey?)] = [
            (.fajr, .sunrise),
            (.dhuhr, .asr),
            (.asr, .maghrib),
            (.maghrib, .isha),
            (.isha, nil), // closes at the next day's Fajr
        ]

        var result: [PrayerReminder] = []

        for (prayer, boundary) in closers {
            guard let window = byKey[prayer] else { continue }

            let deadline: Date
            let windowStart: Date
            if let boundary, let entry = byKey[boundary] {
                // Intraday window: the next boundary closes it.
                deadline = entry.date
                windowStart = window.date
            } else if prayer == .isha, let fajr = byKey[.fajr], fajr.date > now {
                // Small hours after rollover: Isha closes at today's Fajr,
                // and the Isha that opened this window was yesterday's —
                // already behind us, so there is nothing to clamp against.
                deadline = fajr.date
                windowStart = .distantPast
            } else if prayer == .isha, let tomorrow = tomorrowFajr {
                // Evening: tonight's Isha opens at today's entry.
                deadline = tomorrow.date
                windowStart = window.date
            } else {
                continue
            }

            // A long lead must not announce an ending before the window has
            // even opened (a 90-minute lead overshoots a short Fajr gap); the
            // one-minute offset also keeps clear of the adhan at window start.
            let fireDate = max(
                deadline.addingTimeInterval(-lead),
                windowStart.addingTimeInterval(60)
            )
            guard fireDate < deadline else { continue }
            result.append(
                PrayerReminder(subject: .prayer(prayer), fireDate: fireDate, deadline: deadline)
            )
        }

        // Duha: fixed lead, window opening with the sunrise it follows.
        if let sunrise = byKey[.sunrise], let dhuhr = byKey[.dhuhr] {
            let fireDate = max(
                dhuhr.date.addingTimeInterval(-duhaLead),
                sunrise.date.addingTimeInterval(60)
            )
            if fireDate < dhuhr.date {
                result.append(
                    PrayerReminder(subject: .duha, fireDate: fireDate, deadline: dhuhr.date)
                )
            }
        }

        return result
    }

    /// Pure trigger logic — which reminders' instants have arrived within the
    /// grace window, are not already fired, and are enabled.
    static func dueReminders(
        today: [PrayerEntry],
        tomorrowFajr: PrayerEntry?,
        now: Date,
        lead: TimeInterval,
        graceWindow: TimeInterval = ReminderScheduler.graceWindow,
        alreadyFired: Set<String>,
        isEnabled: (PrayerReminder) -> Bool
    ) -> [PrayerReminder] {
        reminders(today: today, tomorrowFajr: tomorrowFajr, now: now, lead: lead)
            .filter { reminder in
                let lag = now.timeIntervalSince(reminder.fireDate)
                return lag >= 0
                    && lag <= graceWindow
                    && !alreadyFired.contains(reminder.id)
                    && isEnabled(reminder)
            }
    }
}
