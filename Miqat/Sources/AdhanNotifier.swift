import AppKit
import Foundation
import UserNotifications

/// Anything that can post an adhan banner. Lets the scheduler and its tests
/// work without the notification framework.
protocol AdhanNotifying: AnyObject {
    func requestAuthorization()
    func post(title: String, body: String)
}

/// Posts the prayer-time banner via UserNotifications.
///
/// The banner is silent: the adhan itself is played through `AdhanPlayer`,
/// and a second notification sound would only clash with it.
final class SystemAdhanNotifier: NSObject, ObservableObject, AdhanNotifying {

    /// Whether macOS currently lets Miqat show banners. Drives the
    /// "banners are off" hint in Settings.
    @Published private(set) var bannersAllowed = false

    /// Invoked on the main queue when the user clicks a delivered banner.
    var onActivated: (() -> Void)?

    /// `UNUserNotificationCenter` requires a proper app bundle; the bare SPM
    /// executable (`swift run`, test runners) is not one, so we degrade to
    /// sound-only rather than crash.
    private static var isAppBundled: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    private let center: UNUserNotificationCenter?

    override init() {
        center = Self.isAppBundled ? UNUserNotificationCenter.current() : nil
        super.init()
        center?.delegate = self
        refreshAuthorizationStatus()
    }

    func requestAuthorization() {
        guard let center else { return }
        // Prompts only when never decided; a no-op when already granted and
        // an immediate denial callback when the user said no.
        center.requestAuthorization(options: [.alert]) { [weak self] _, _ in
            self?.refreshAuthorizationStatus()
        }
    }

    /// True when the adhan can also show banners (app bundle + permission).
    var supportsBanners: Bool { center != nil }

    func refreshAuthorizationStatus() {
        guard let center else { return }
        center.getNotificationSettings { [weak self] settings in
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                self?.bannersAllowed = allowed
            }
        }
    }

    /// Opens System Settings straight to Miqat's notification pane.
    func openSystemSettings() {
        guard let identifier = Bundle.main.bundleIdentifier,
              let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?\(identifier)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func post(title: String, body: String) {
        guard let center else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: "miqat.adhan.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}

extension SystemAdhanNotifier: UNUserNotificationCenterDelegate {
    /// Show the banner even when Miqat's popover happens to be open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    /// Clicking the banner silences the adhan.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async { [weak self] in
                self?.onActivated?()
            }
        }
        completionHandler()
    }
}
