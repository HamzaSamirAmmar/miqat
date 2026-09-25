import AppKit
import Combine
import Foundation
import UserNotifications

/// Anything that can post an adhan banner. Lets the scheduler and its tests
/// work without the notification framework.
protocol AdhanNotifying: AnyObject {
    func requestAuthorization()
    func post(title: String, body: String)
}

/// Anything that can post a time-end reminder notification. Keeps the
/// reminder scheduler and its tests free of the notification framework.
protocol ReminderNotifying: AnyObject {
    func requestAuthorization()
    func postReminder(title: String, body: String)
}

/// Posts the prayer-time banner via UserNotifications.
///
/// The banner is silent: the adhan itself is played through `AdhanPlayer`,
/// and a second notification sound would only clash with it. Reminder
/// notifications (`postReminder`) are the opposite — plain notifications
/// that carry the default sound.
final class SystemAdhanNotifier: NSObject, ObservableObject, AdhanNotifying, ReminderNotifying {

    /// Whether macOS currently lets Miqat show banners. Drives the
    /// "banners are off" hint in Settings.
    @Published private(set) var bannersAllowed = false

    /// Invoked on the main queue when the user clicks a delivered banner or
    /// taps its "Stop Adhan" action — both silence the adhan.
    var onActivated: (() -> Void)?

    /// Category identifier that tags adhan banners so they carry the
    /// "Stop Adhan" action button.
    private static let categoryID = "miqat.adhan"
    /// The action behind the banner's "Stop Adhan" button.
    private static let stopActionID = "miqat.adhan.stop"
    /// Tags reminder notifications (no actions; also tells `willPresent` to
    /// keep the default sound when the popover is open).
    private static let reminderCategoryID = "miqat.reminder"

    private var localizationCancellable: AnyCancellable?

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
        registerAdhanCategory()
        refreshAuthorizationStatus()

        // Action titles are captured at registration — re-register when the
        // in-app language changes so the button follows the interface.
        localizationCancellable = Localization.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.registerAdhanCategory() }
    }

    /// Gives the adhan banner its localized "Stop Adhan" action button.
    private func registerAdhanCategory() {
        guard let center else { return }
        let stop = UNNotificationAction(
            identifier: Self.stopActionID,
            title: Localization.shared.string("adhan.notification.stop")
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [stop],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() {
        guard let center else { return }
        // Prompts only when never decided; a no-op when already granted and
        // an immediate denial callback when the user said no. Sound is part
        // of the ask because reminders rely on the default notification sound.
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
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
            content.categoryIdentifier = Self.categoryID
            let request = UNNotificationRequest(
                identifier: "miqat.adhan.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    func postReminder(title: String, body: String) {
        guard let center else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = Self.reminderCategoryID
            let request = UNNotificationRequest(
                identifier: "miqat.reminder.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}

extension SystemAdhanNotifier: UNUserNotificationCenterDelegate {
    /// Show the banner even when Miqat's popover happens to be open. Adhan
    /// banners stay silent (the adhan is playing); reminders keep their
    /// default sound.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.content.categoryIdentifier == Self.reminderCategoryID {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.banner, .list])
        }
    }

    /// Clicking the banner or tapping its "Stop Adhan" button silences the
    /// adhan.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let silences = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            || response.actionIdentifier == Self.stopActionID
        if silences {
            DispatchQueue.main.async { [weak self] in
                self?.onActivated?()
            }
        }
        completionHandler()
    }
}
