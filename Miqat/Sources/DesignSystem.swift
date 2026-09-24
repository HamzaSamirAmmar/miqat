import AppKit
import SwiftUI

// MARK: - Colors

extension Color {
    /// A color that resolves per appearance (light / dark menu bar popover).
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Brand palette, taken from the app icon (deep teal arch, coral trim).
enum Brand {
    /// Primary accent — the icon's teal, lifted in dark mode for contrast.
    static let accent = Color(light: NSColor(hex: 0x0E7C86), dark: NSColor(hex: 0x4CC9C6))
    /// Soft fill for selected / highlighted surfaces.
    static let accentFill = Color(light: NSColor(hex: 0x0E7C86).withAlphaComponent(0.11),
                                  dark: NSColor(hex: 0x4CC9C6).withAlphaComponent(0.16))
    /// The icon's coral trim — used sparingly, for the brand mark only.
    static let coral = Color(hex: 0xEE7A5C)
    static let teal = Color(hex: 0x0B5F68)
}

/// The hero card's sky: a gradient for the stretch of day leading up to each
/// prayer, so the card reads the time of day at a glance. Every pair keeps
/// white text at or near WCAG AA contrast in both appearances.
struct SkyPalette {
    let top: Color
    let bottom: Color

    static func leading(to prayer: PrayerKey) -> SkyPalette {
        switch prayer {
        case .fajr:     // deep night
            return SkyPalette(top: Color(hex: 0x111A40), bottom: Color(hex: 0x2A3775))
        case .sunrise:  // pre-dawn indigo warming to mauve
            return SkyPalette(top: Color(hex: 0x28306F), bottom: Color(hex: 0x87467A))
        case .dhuhr:    // clear morning sky
            return SkyPalette(top: Color(hex: 0x0F5A96), bottom: Color(hex: 0x2476B4))
        case .asr:      // bright afternoon, the brand teal
            return SkyPalette(top: Color(hex: 0x0A5961), bottom: Color(hex: 0x1C7C78))
        case .maghrib:  // late-afternoon amber
            return SkyPalette(top: Color(hex: 0x8C3F18), bottom: Color(hex: 0xB35626))
        case .isha:     // dusk purple
            return SkyPalette(top: Color(hex: 0x3E2766), bottom: Color(hex: 0x6E3468))
        }
    }
}

// MARK: - Screen chrome

/// Title bar for secondary screens: back chevron, centered title.
struct ScreenHeader: View {
    let title: String
    let onBack: () -> Void
    @ObservedObject private var localization = Localization.shared

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)

            HStack {
                Button(action: onBack) {
                    Image(systemName: localization.isRTL ? "chevron.right" : "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help(localization.string("location.back"))
                .accessibilityLabel(localization.string("location.back"))

                Spacer()
            }
        }
    }
}

/// Grouped form section in the style of System Settings: small caps
/// header, rounded container, rows separated by inset dividers.
struct FormSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
    }
}

/// One form row: label (with optional caption) leading, control trailing.
struct FormRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// Divider between form rows, inset like native grouped lists.
struct FormDivider: View {
    var body: some View {
        Divider().padding(.leading, 10)
    }
}

// MARK: - Buttons & interaction

/// Borderless icon button with a soft circular hover state.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration)
    }

    private struct IconButtonBody: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(Color.primary.opacity(
                        configuration.isPressed ? 0.14 : (isHovered && isEnabled ? 0.08 : 0)
                    ))
                )
                .contentShape(Circle())
                .onHover { isHovered = $0 }
        }
    }
}

/// Capsule "chip" button, e.g. the location switcher.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration)
    }

    private struct PillBody: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.primary.opacity(
                        configuration.isPressed ? 0.14 : (isHovered ? 0.10 : 0.06)
                    ))
                )
                .contentShape(Capsule())
                .onHover { isHovered = $0 }
        }
    }
}

/// Full-width list row button with a hover highlight.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .modifier(HoverHighlight(pressed: configuration.isPressed))
    }
}

/// Soft row highlight on hover, echoing the native list feel.
struct HoverHighlight: ViewModifier {
    var pressed = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(pressed ? 0.12 : (isHovered ? 0.06 : 0)))
            )
            .onHover { isHovered = $0 }
    }
}

// MARK: - Brand mark

/// The mihrab glyph on a teal tile — used where the app introduces itself.
struct BrandMark: View {
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(hex: 0x14808A), Brand.teal],
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(width: size, height: size)
            .overlay(
                Image(nsImage: MenuBarIcon.image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: size * 0.52)
                    .foregroundStyle(Color(hex: 0xFBE9D7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Brand.coral.opacity(0.9), lineWidth: max(1, size * 0.035))
                    .padding(size * 0.06)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Motion helpers

extension View {
    /// Rolling-digit transition for ticking numbers where the OS supports it.
    @ViewBuilder
    func numericTransition() -> some View {
        if #available(macOS 14.0, *) {
            contentTransition(.numericText(countsDown: true))
        } else {
            self
        }
    }
}
