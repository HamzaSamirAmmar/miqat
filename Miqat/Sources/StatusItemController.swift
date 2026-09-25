import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    /// Posted by the app's "Settings" menu command to open the popover on
    /// the settings screen.
    static let miqatOpenSettings = Notification.Name("miqat.openSettings")
}

/// Owns the menu bar item via AppKit's `NSStatusItem`.
///
/// Same approach as NetHUD: SwiftUI's `MenuBarExtra` label mis-renders custom
/// content, so the live label is an attributed string on the status item's
/// button; the dropdown remains SwiftUI, shown in a popover on click.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: PrayerScheduleStore
    private let locationManager: LocationManager
    private let adhanPlayer: AdhanPlayer
    private let adhanNotifier: SystemAdhanNotifier
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var storeCancellable: AnyCancellable?
    private var localizationCancellable: AnyCancellable?
    private var openSettingsObserver: NSObjectProtocol?
    private var globalEventMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?
    private var lastCloseTime: TimeInterval = 0

    init(store: PrayerScheduleStore, locationManager: LocationManager, adhanPlayer: AdhanPlayer, adhanNotifier: SystemAdhanNotifier) {
        self.store = store
        self.locationManager = locationManager
        self.adhanPlayer = adhanPlayer
        self.adhanNotifier = adhanNotifier
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.delegate = self
        resetContent()

        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .miqatOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in
            self?.openSettings()
        }

        if let button = statusItem.button {
            button.setAccessibilityLabel("Miqat prayer times")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        storeCancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.renderTitle() }

        // Prayer names in the title are localized — re-render on language change.
        localizationCancellable = Localization.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.renderTitle() }

        renderTitle()
    }

    deinit {
        tearDownEventMonitors()
        if let openSettingsObserver {
            NotificationCenter.default.removeObserver(openSettingsObserver)
        }
    }

    // MARK: - Title rendering

    private func renderTitle() {
        guard let button = statusItem.button else { return }

        // Fully monospaced font + fixed-width countdown → the item's width
        // never changes while ticking, so menu bar neighbors never shift.
        // Arabic prayer names render through the font cascade.
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let base = Localization.shared.string("tooltip.base")

        guard let next = store.next else {
            button.image = MenuBarIcon.image
            button.imagePosition = .imageLeft
            button.attributedTitle = NSAttributedString(string: " –:–", attributes: [.font: font])
            button.toolTip = base
            return
        }

        let interval = next.date.timeIntervalSince(store.now)
        let countdown = Format.countdown(interval)

        switch store.titleStyle {
        case .icon:
            button.image = MenuBarIcon.image
            button.attributedTitle = NSAttributedString(string: "", attributes: [.font: font])
        case .countdown:
            button.image = nil
            button.attributedTitle = NSAttributedString(string: countdown, attributes: [.font: font])
        case .labeled:
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: "\(next.key.displayName) \(countdown)",
                attributes: [.font: font]
            )
        }

        button.toolTip = "\(base) — \(next.key.displayName) \(Format.remaining(interval))"
    }

    // MARK: - Content Management

    private func resetContent() {
        locationManager.clearSearch()
        let hosting = NSHostingController(
            rootView: MenuBarView(
                store: store,
                location: locationManager,
                adhanPlayer: adhanPlayer,
                adhanNotifier: adhanNotifier,
                initialScreen: .schedule
            )
        )
        // Let the popover follow SwiftUI's size as screens change; otherwise it
        // keeps the size measured at first show and clips the Settings screen.
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastCloseTime < 0.2 {
                return
            }
            showPopover()
        }
    }

    /// ⌘, / the "Settings" menu item: land the popover on the settings screen.
    private func openSettings() {
        if popover.isShown {
            closePopover()
        }
        let hosting = NSHostingController(
            rootView: MenuBarView(
                store: store,
                location: locationManager,
                adhanPlayer: adhanPlayer,
                adhanNotifier: adhanNotifier,
                initialScreen: .settings
            )
        )
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            popover.contentSize = view.fittingSize
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        setupEventMonitors()
    }

    @objc private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        if popover.isShown {
            popover.close()
        }
    }

    // MARK: - Event Monitors (Unfocus dismissal)

    private func setupEventMonitors() {
        tearDownEventMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover()
            }
        }

        if let window = popover.contentViewController?.view.window {
            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.closePopover()
            }
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func tearDownEventMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let observer = resignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            resignKeyObserver = nil
        }
        if let observer = resignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            resignActiveObserver = nil
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        lastCloseTime = ProcessInfo.processInfo.systemUptime
        tearDownEventMonitors()
        resetContent()
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        true
    }
}
