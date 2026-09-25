import AppKit
import SwiftUI

@main
struct MiqatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // Settings live in the menu bar popover, not in a scene window.
            // Replace the system "Settings…" item so it can never open the
            // empty scene window — ⌘, opens the popover on Settings instead.
            CommandGroup(replacing: .appSettings) {
                Button(Localization.shared.string("nav.settings")) {
                    NotificationCenter.default.post(name: .miqatOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PrayerScheduleStore()
    private let locationManager = LocationManager()
    private let adhanPlayer = AdhanPlayer()
    private let adhanNotifier = SystemAdhanNotifier()
    private var adhanScheduler: AdhanScheduler?
    private var reminderScheduler: ReminderScheduler?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        locationManager.onPlaceDetected = { [weak store] place in
            store?.place = place
        }

        // Automatic mode follows the Mac: re-detect at launch and after
        // sleep (e.g. opening the lid in another city).
        refreshAutomaticLocation()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Give Wi-Fi a moment to reconnect — positioning needs it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                self?.refreshAutomaticLocation()
            }
        }

        adhanNotifier.onActivated = { [adhanPlayer] in
            adhanPlayer.stop()
        }
        let scheduler = AdhanScheduler(store: store, player: adhanPlayer, notifier: adhanNotifier)
        scheduler.start()
        adhanScheduler = scheduler

        let reminders = ReminderScheduler(store: store, notifier: adhanNotifier)
        reminders.start()
        reminderScheduler = reminders

        statusItemController = StatusItemController(
            store: store,
            locationManager: locationManager,
            adhanPlayer: adhanPlayer,
            adhanNotifier: adhanNotifier
        )
    }

    private func refreshAutomaticLocation() {
        guard store.place?.source == .detected else { return }
        locationManager.refreshSilently()
    }
}
