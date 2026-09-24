import Foundation

/// Menu bar title presentation.
enum TitleStyle: String, CaseIterable, Identifiable {
    /// "Asr 1:23" — prayer name plus countdown.
    case labeled
    /// "🕌 1:23" — mosque glyph plus countdown.
    case compact

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .labeled: return "Labeled"
        case .compact: return "Compact"
        }
    }
}
