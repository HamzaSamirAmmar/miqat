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
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        locationManager.onPlaceDetected = { [weak store] place in
            store?.place = place
        }
        statusItemController = StatusItemController(store: store, locationManager: locationManager)
    }
}
