import Combine
import Foundation

/// Watches the store's clock and plays the adhan (plus a banner) when an
/// enabled prayer's time arrives.
///
/// The store already ticks every second and catches wake/clock changes, so
/// the scheduler only has to notice entries crossing `now`.
final class AdhanScheduler: ObservableObject {

    /// A prayer missed by more than this window does not fire — a Mac that
    /// slept through Fajr must not blast a belated adhan on wake.
    static let graceWindow: TimeInterval = 90

    private let store: PrayerScheduleStore
    private let player: AdhanPlaying
    private let notifier: AdhanNotifying
    private var cancellable: AnyCancellable?
    private var firedEntryIDs: Set<String> = []
    /// First entry of the schedule the fired set belongs to; resets on rollover.
    private var firedDayKey: Date?
    private var activity: NSObjectProtocol?

    init(store: PrayerScheduleStore, player: AdhanPlaying, notifier: AdhanNotifying) {
        self.store = store
        self.player = player
        self.notifier = notifier
    }

    deinit {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    func start() {
        notifier.requestAuthorization()

        // App Nap can throttle the store's timer while the popover is closed;
        // holding this activity keeps adhans firing on time.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Miqat adhan scheduling"
        )

        cancellable = store.$now
            .receive(on: DispatchQueue.main)
            .sink { [weak self] now in
                self?.process(self?.store.today ?? [], now: now)
            }
    }

    // MARK: - Firing

    /// Examines the schedule against `now`, firing anything due. Internal so
    /// tests can drive it with synthetic times and spy player/notifier.
    func process(_ entries: [PrayerEntry], now: Date) {
        // A new schedule (day rollover at the place) re-arms everything.
        if let dayKey = entries.first?.date, dayKey != firedDayKey {
            firedDayKey = dayKey
            firedEntryIDs = []
        }

        let due = Self.dueEntries(
            in: entries,
            now: now,
            alreadyFired: firedEntryIDs
        ) { [store] entry in
            store.isAdhanEnabled(entry.key)
        }

        for entry in due {
            firedEntryIDs.insert(entry.id)
            fire(entry)
        }
    }

    private func fire(_ entry: PrayerEntry) {
        let track = store.adhanTrack(for: entry.key)
        player.play(trackID: track.id)
        notifier.post(
            title: Localization.shared.string("adhan.notification.title", entry.key.displayName),
            body: track.displayName
        )
    }

    /// Pure trigger logic — which entries' instants have arrived within the
    /// grace window, are not already fired, and are enabled.
    static func dueEntries(
        in entries: [PrayerEntry],
        now: Date,
        graceWindow: TimeInterval = AdhanScheduler.graceWindow,
        alreadyFired: Set<String>,
        isEnabled: (PrayerEntry) -> Bool
    ) -> [PrayerEntry] {
        entries.filter { entry in
            let lag = now.timeIntervalSince(entry.date)
            return lag >= 0
                && lag <= graceWindow
                && !alreadyFired.contains(entry.id)
                && isEnabled(entry)
        }
    }
}
