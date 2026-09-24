import SwiftUI

@main
struct MiqatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PrayerScheduleStore()
    private let locationManager = LocationManager()
    private let adhanPlayer = AdhanPlayer()
    private let adhanNotifier = SystemAdhanNotifier()
    private var adhanScheduler: AdhanScheduler?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        locationManager.onPlaceDetected = { [weak store] place in
            store?.place = place
        }

        adhanNotifier.onActivated = { [adhanPlayer] in
            adhanPlayer.stop()
        }
        let scheduler = AdhanScheduler(store: store, player: adhanPlayer, notifier: adhanNotifier)
        scheduler.start()
        adhanScheduler = scheduler

        statusItemController = StatusItemController(
            store: store,
            locationManager: locationManager,
            adhanPlayer: adhanPlayer,
            adhanNotifier: adhanNotifier
        )
    }
}
