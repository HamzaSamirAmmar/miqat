import Foundation

/// Menu bar title theme.
enum TitleStyle: String, CaseIterable, Identifiable {
    /// "🕌" — just the icon, Control Center style. The countdown lives in the
    /// tooltip and the popover.
    case icon
    /// "1:23" — the countdown to the next prayer only.
    case countdown
    /// "Asr 1:23" — prayer name plus countdown.
    case labeled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .icon: return Localization.shared.string("theme.icon")
        case .countdown: return Localization.shared.string("theme.countdown")
        case .labeled: return Localization.shared.string("theme.labeled")
        }
    }

    /// Pre-1.1 builds had a "compact" style (icon + countdown); it maps to
    /// `countdown`, which preserves the live readout.
    static func migrate(_ storedRawValue: String) -> TitleStyle? {
        if let style = TitleStyle(rawValue: storedRawValue) { return style }
        return storedRawValue == "compact" ? .countdown : nil
    }
}
