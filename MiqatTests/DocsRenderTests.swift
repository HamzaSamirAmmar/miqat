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

        // MARK: - Popover snapshots

        func snapshotPopover(dark: Bool) -> NSBitmapImageRep? {
            let hosting = NSHostingController(
                rootView: MenuBarView(store: store, location: locationManager)
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

        func snapshotSettings(dark: Bool) -> NSBitmapImageRep? {
            let hosting = NSHostingController(
                rootView: SettingsView(store: store, onDismiss: {})
                    .padding(16)
                    .frame(width: 340)
                    .environment(\.locale, Localization.shared.locale)
                    .environment(\.layoutDirection, Localization.shared.layoutDirection)
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

        // MARK: - Menu bar strips

        func makeBitmap(width: CGFloat, height: CGFloat) -> (NSBitmapImageRep, NSGraphicsContext) {
            let scale: CGFloat = 2 // Retina-crisp output
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            )!
            rep.size = NSSize(width: width, height: height)
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            context.cgContext.scaleBy(x: scale, y: scale)
            return (rep, context)
        }

        func statusStrip(title: String, dark: Bool) -> (image: NSImage, width: CGFloat) {
            let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let icon = MenuBarIcon.image
            let attributed = NSAttributedString(
                string: title,
                attributes: [.font: font, .foregroundColor: dark ? NSColor.white : NSColor.black]
            )

            let leading: CGFloat = 12
            let gap: CGFloat = 6
            let height: CGFloat = 36
            let titleWidth = title.isEmpty ? 0 : attributed.size().width
            let width = leading + icon.size.width + (title.isEmpty ? 0 : gap + titleWidth) + leading

            let (rep, context) = makeBitmap(width: width, height: height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            defer { NSGraphicsContext.restoreGraphicsState() }

            (dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.95, alpha: 1)).set()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

            let iconRect = NSRect(x: leading, y: (height - icon.size.height) / 2,
                                  width: icon.size.width, height: icon.size.height)
            if dark {
                let tinted = NSImage(size: icon.size)
                tinted.lockFocus()
                icon.draw(in: NSRect(origin: .zero, size: icon.size))
                NSColor.white.set()
                NSRect(origin: .zero, size: icon.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(in: iconRect)
            } else {
                icon.draw(in: iconRect)
            }

            if !title.isEmpty {
                let titleSize = attributed.size()
                attributed.draw(at: NSPoint(x: leading + icon.size.width + gap,
                                            y: (height - titleSize.height) / 2))
            }

            let image = NSImage(size: NSSize(width: width, height: height))
            image.addRepresentation(rep)
            return (image, width)
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

        // Menu bar strips (light + dark), Labeled theme.
        for (dark, name) in [(false, "menubar-light.png"), (true, "menubar-dark.png")] {
            let (strip, _) = statusStrip(title: "Asr 1:23", dark: dark)
            try write(strip, name)
        }

        // Themes: the three menu bar styles stacked with captions.
        let rows: [(label: String, title: String)] = [
            ("Icon", ""),
            ("Countdown", "1:23"),
            ("Labeled", "Asr 1:23"),
        ]

        let strips = rows.map { statusStrip(title: $0.title, dark: false) }
        let rowHeight: CGFloat = 36
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let labelHeight: CGFloat = 18
        let padding: CGFloat = 18
        let rowSpacing: CGFloat = 14
        let themesWidth = strips.map(\.width).max()! + padding * 2
        let themesHeight = CGFloat(rows.count) * (rowHeight + labelHeight + rowSpacing) - rowSpacing + padding

        let (rep, context) = makeBitmap(width: themesWidth, height: themesHeight)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor(calibratedWhite: 0.96, alpha: 1).set()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: themesWidth, height: themesHeight),
                     xRadius: 16, yRadius: 16).fill()

        var y = padding
        for ((row, _), strip) in zip(rows, strips).reversed() {
            strip.image.draw(in: NSRect(origin: NSPoint(x: (themesWidth - strip.width) / 2, y: y),
                                        size: strip.image.size))
            let label = NSAttributedString(
                string: row,
                attributes: [.font: labelFont, .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1)]
            )
            label.draw(at: NSPoint(x: (themesWidth - label.size().width) / 2, y: y + rowHeight + 1))
            y += rowHeight + labelHeight + rowSpacing
        }

        try write(rep, "themes.png")
    }
}
