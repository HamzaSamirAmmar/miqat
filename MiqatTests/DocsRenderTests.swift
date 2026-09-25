import AppKit
import SwiftUI
import XCTest
@testable import Miqat

/// Regenerates the Docs/ screenshots offscreen by snapshotting the real
/// SwiftUI views — no screen-recording permission needed. Run explicitly:
///
///     MIQAT_RENDER_DOCS=1 scripts/render_docs.sh
///
/// Skipped during normal test runs so CI never dirties the working tree.
final class DocsRenderTests: XCTestCase {

    func testRenderScreenshots() throws {
        guard ProcessInfo.processInfo.environment["MIQAT_RENDER_DOCS"] == "1" else {
            throw XCTSkip("screenshot renderer — set MIQAT_RENDER_DOCS=1 to run")
        }

        let docsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MiqatTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Docs")
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)

        _ = NSApplication.shared

        // Photogenic, deterministic state: Casablanca, English, MWL.
        if let casablanca = CityDatabase.search("casablanca").first {
            UserDefaults.standard.set(CityDatabase.place(from: casablanca).persistedValue!, forKey: "miqat.place")
        }
        UserDefaults.standard.set(CalculationMethodChoice.muslimWorldLeague.rawValue, forKey: "miqat.method")
        Localization.shared.language = .english

        let store = PrayerScheduleStore()
        let locationManager = LocationManager()
        let adhanPlayer = AdhanPlayer()
        let adhanNotifier = SystemAdhanNotifier()

        // MARK: - Popover snapshots

        func snapshot(dark: Bool, screen: ActiveScreen) -> NSBitmapImageRep? {
            let hosting = NSHostingController(
                rootView: MenuBarView(
                    store: store, location: locationManager, adhanPlayer: adhanPlayer,
                    adhanNotifier: adhanNotifier, initialScreen: screen
                )
                .background(Color(dark ? NSColor(calibratedWhite: 0.14, alpha: 1) : NSColor(calibratedWhite: 0.98, alpha: 1)))
            )
            hosting.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

            let size = hosting.view.fittingSize
            hosting.view.setFrameSize(size)
            hosting.view.layoutSubtreeIfNeeded()

            guard let rep = hosting.view.bitmapImageRepForCachingDisplay(in: hosting.view.bounds) else { return nil }
            hosting.view.cacheDisplay(in: hosting.view.bounds, to: rep)
            return rep
        }

        func snapshotPopover(dark: Bool) -> NSBitmapImageRep? {
            snapshot(dark: dark, screen: .schedule)
        }

        func snapshotSettings(dark: Bool) -> NSBitmapImageRep? {
            snapshot(dark: dark, screen: .settings)
        }

        // MARK: - Writing

        func write(_ rep: NSBitmapImageRep, _ name: String) throws {
            guard let data = rep.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "render", code: 1)
            }
            try data.write(to: docsURL.appendingPathComponent(name))
            print("Docs/\(name) — \(rep.pixelsWide)×\(rep.pixelsHigh)")
        }

        func write(_ image: NSImage, _ name: String) throws {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "render", code: 2)
            }
            try data.write(to: docsURL.appendingPathComponent(name))
            print("Docs/\(name)")
        }

        // Dropdown + hero.
        if let light = snapshotPopover(dark: false) {
            try write(light, "dropdown-light.png")
        }
        if let dark = snapshotPopover(dark: true) {
            try write(dark, "dropdown-dark.png")
            try write(dark, "hero.png")
        }

        // Arabic dropdown snapshots
        Localization.shared.language = .arabic
        if let arDark = snapshotPopover(dark: true) {
            try write(arDark, "dropdown-ar-dark.png")
        }
        if let arLight = snapshotPopover(dark: false) {
            try write(arLight, "dropdown-ar-light.png")
        }
        Localization.shared.language = .english

        // Settings snapshots
        if let settingsDark = snapshotSettings(dark: true) {
            try write(settingsDark, "settings-dark.png")
        }
        if let settingsLight = snapshotSettings(dark: false) {
            try write(settingsLight, "settings-light.png")
        }

        // Menu bar mockups: the whole bar (so it reads as a real macOS menu
        // bar) and a theme comparison, each in light and dark.
        let countdown = Format.countdown(83 * 60)
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try write(MenuBarMock.fullBar(title: "Asr \(countdown)", dark: dark), "menubar-\(suffix).png")
            try write(MenuBarMock.themes(countdown: countdown, dark: dark), "themes-\(suffix).png")
        }
    }
}

// MARK: - Menu bar mockups

/// Draws macOS-style menu bars around Miqat's status item, using the same
/// glyph, font, and title format as `StatusItemController`.
private enum MenuBarMock {

    enum Item {
        case miqat(icon: Bool, title: String)
        case symbol(String)
        case text(String, bold: Bool = false)
    }

    struct Palette {
        let dark: Bool
        var bar: NSColor { dark ? NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
                                : NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.94, alpha: 1) }
        var ink: NSColor { dark ? NSColor(calibratedWhite: 0.96, alpha: 1) : NSColor(calibratedWhite: 0.08, alpha: 1) }
        var highlight: NSColor { dark ? NSColor(calibratedWhite: 1, alpha: 0.2) : NSColor(calibratedWhite: 0, alpha: 0.11) }
        var card: NSColor { dark ? NSColor(calibratedWhite: 0.11, alpha: 1) : NSColor(calibratedWhite: 1, alpha: 1) }
        var stroke: NSColor { dark ? NSColor(calibratedWhite: 1, alpha: 0.1) : NSColor(calibratedWhite: 0, alpha: 0.1) }
        var secondary: NSColor { dark ? NSColor(calibratedWhite: 0.62, alpha: 1) : NSColor(calibratedWhite: 0.42, alpha: 1) }
    }

    static let barHeight: CGFloat = 28
    static let itemSpacing: CGFloat = 16
    static let titleFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    static let menuFont = NSFont.menuBarFont(ofSize: 13)

    // MARK: Canvas

    /// A 2× bitmap whose drawing space is `size` points (AppKit maps the
    /// rep's point size onto its pixels — no extra scale needed).
    static func render(_ size: NSSize, _ draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    static func symbol(_ name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    }

    // MARK: Bar

    static func width(of item: Item) -> CGFloat {
        switch item {
        case let .miqat(icon, title):
            let titleWidth = title.isEmpty ? 0 : NSAttributedString(string: title, attributes: [.font: titleFont]).size().width
            return (icon ? MenuBarIcon.image.size.width : 0) + (icon && !title.isEmpty ? 4 : 0) + titleWidth
        case let .symbol(name):
            return symbol(name).size.width
        case let .text(string, bold):
            let font = bold ? NSFont.boldSystemFont(ofSize: 13) : menuFont
            return NSAttributedString(string: string, attributes: [.font: font]).size().width
        }
    }

    /// Draws `items` left to right starting at `x`, vertically centered in
    /// `bar`. Miqat's item gets the "open" highlight pill.
    static func draw(_ items: [Item], from x: CGFloat, in bar: NSRect, palette: Palette) {
        var x = x
        for item in items {
            let w = width(of: item)
            let midY = bar.midY
            switch item {
            case let .miqat(icon, title):
                palette.highlight.set()
                NSBezierPath(roundedRect: NSRect(x: x - 7, y: midY - 11, width: w + 14, height: 22),
                             xRadius: 6, yRadius: 6).fill()
                var cursor = x
                if icon {
                    let glyph = MenuBarIcon.image
                    tinted(glyph, palette.ink).draw(in: NSRect(x: cursor, y: midY - glyph.size.height / 2,
                                                              width: glyph.size.width, height: glyph.size.height))
                    cursor += glyph.size.width + 4
                }
                if !title.isEmpty {
                    let text = NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: palette.ink])
                    text.draw(at: NSPoint(x: cursor, y: midY - text.size().height / 2))
                }
            case let .symbol(name):
                let image = tinted(symbol(name), palette.ink)
                image.draw(in: NSRect(x: x, y: midY - image.size.height / 2, width: image.size.width, height: image.size.height))
            case let .text(string, bold):
                let font = bold ? NSFont.boldSystemFont(ofSize: 13) : menuFont
                let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: palette.ink])
                text.draw(at: NSPoint(x: x, y: midY - text.size().height / 2))
            }
            x += w + itemSpacing
        }
    }

    static func rowWidth(_ items: [Item]) -> CGFloat {
        items.map(width(of:)).reduce(0, +) + itemSpacing * CGFloat(max(items.count - 1, 0))
    }

    static let systemItems: [Item] = [
        .symbol("wifi"), .symbol("battery.75percent"), .symbol("magnifyingglass"),
        .symbol("switch.2"), .text("Thu 24 Sep  2:37 PM"),
    ]

    // MARK: Images

    /// The complete menu bar: app menus on the left, Miqat among the status
    /// items on the right — instantly recognizable as a Mac menu bar.
    static func fullBar(title: String, dark: Bool) -> NSBitmapImageRep {
        let palette = Palette(dark: dark)
        let size = NSSize(width: 700, height: barHeight)
        return render(size) {
            let bar = NSRect(origin: .zero, size: size)
            palette.bar.set()
            NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8).fill()

            draw([.symbol("apple.logo"), .text("Finder", bold: true), .text("File"), .text("Edit"),
                  .text("View"), .text("Go"), .text("Window")],
                 from: 14, in: bar, palette: palette)

            let right: [Item] = [.miqat(icon: false, title: title)] + systemItems
            draw(right, from: size.width - 14 - rowWidth(right), in: bar, palette: palette)
        }
    }

    /// The three title styles side by side with what each one shows.
    static func themes(countdown: String, dark: Bool) -> NSBitmapImageRep {
        let palette = Palette(dark: dark)
        let rows: [(name: String, detail: String, item: Item)] = [
            ("Icon", "Just the glyph — countdown in the tooltip", .miqat(icon: true, title: "")),
            ("Countdown", "Time left until the next prayer", .miqat(icon: false, title: countdown)),
            ("Labeled", "Next prayer’s name plus the countdown", .miqat(icon: false, title: "Asr \(countdown)")),
        ]
        let neighbors: [Item] = [.symbol("wifi"), .symbol("battery.75percent"), .text("2:37 PM")]

        let padding: CGFloat = 20
        let rowHeight: CGFloat = 60
        let barWidth: CGFloat = 250
        let size = NSSize(width: 600, height: padding * 2 + rowHeight * CGFloat(rows.count))

        return render(size) {
            let card = NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let cardPath = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
            palette.card.set(); cardPath.fill()
            palette.stroke.set(); cardPath.lineWidth = 1; cardPath.stroke()

            for (index, row) in rows.enumerated() {
                let top = size.height - padding - rowHeight * CGFloat(index)
                let midY = top - rowHeight / 2

                if index > 0 {
                    palette.stroke.set()
                    NSRect(x: padding, y: top, width: size.width - padding * 2, height: 1).fill()
                }

                let name = NSAttributedString(string: row.name, attributes: [
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: palette.ink,
                ])
                let detail = NSAttributedString(string: row.detail, attributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: palette.secondary,
                ])
                name.draw(at: NSPoint(x: padding, y: midY + 1))
                detail.draw(at: NSPoint(x: padding, y: midY - detail.size().height - 1))

                let bar = NSRect(x: size.width - padding - barWidth, y: midY - barHeight / 2,
                                 width: barWidth, height: barHeight)
                palette.bar.set()
                NSBezierPath(roundedRect: bar, xRadius: 7, yRadius: 7).fill()
                let items = [row.item] + neighbors
                draw(items, from: bar.maxX - 12 - rowWidth(items), in: bar, palette: palette)
            }
        }
    }
}
