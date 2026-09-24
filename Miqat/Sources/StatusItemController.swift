import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item via AppKit's `NSStatusItem`.
///
/// Same approach as NetHUD: SwiftUI's `MenuBarExtra` label mis-renders custom
/// content, so the live label is an attributed string on the status item's
/// button; the dropdown remains SwiftUI, shown in a popover on click.
final class StatusItemController: NSObject {
    private let store: PrayerScheduleStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var storeCancellable: AnyCancellable?
    private var localizationCancellable: AnyCancellable?

    init(store: PrayerScheduleStore, locationManager: LocationManager, adhanPlayer: AdhanPlayer, adhanNotifier: SystemAdhanNotifier) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(store: store, location: locationManager, adhanPlayer: adhanPlayer, adhanNotifier: adhanNotifier)
        )

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

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let view = popover.contentViewController?.view {
                view.layoutSubtreeIfNeeded()
                popover.contentSize = view.fittingSize
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
