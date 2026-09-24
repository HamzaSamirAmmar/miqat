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
    private var cancellable: AnyCancellable?

    init(store: PrayerScheduleStore, locationManager: LocationManager) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(store: store, location: locationManager)
        )

        if let button = statusItem.button {
            button.toolTip = "Miqat — prayer times"
            button.setAccessibilityLabel("Miqat prayer times")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        cancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.renderTitle() }

        renderTitle()
    }

    // MARK: - Title rendering

    private func renderTitle() {
        guard let button = statusItem.button else { return }

        // Fully monospaced font + fixed-width countdown → the item's width
        // never changes while ticking, so menu bar neighbors never shift.
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        guard let next = store.next else {
            button.attributedTitle = NSAttributedString(string: "🕌 –:–", attributes: [.font: font])
            return
        }

        let countdown = Format.countdown(next.date.timeIntervalSince(store.now))
        let title: String
        switch store.titleStyle {
        case .labeled:
            title = "\(next.key.displayName) \(countdown)"
        case .compact:
            title = "🕌 \(countdown)"
        }

        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
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
