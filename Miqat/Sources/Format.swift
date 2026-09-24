import Foundation

enum Format {

    /// Menu-bar countdown in fixed-width `h:mm` form, e.g. "1:23" or "0:43".
    /// The width only grows past four characters on >9h gaps (possible between
    /// Isha and Fajr at high latitudes); paired with a monospaced font, menu
    /// bar neighbors never jitter while the countdown ticks.
    static func countdown(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded()), 0)
        return String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    /// Human-readable remaining time, e.g. "1h 23m" or "43m".
    static func remaining(_ interval: TimeInterval) -> String {
        let minutes = max(Int((interval / 60).rounded()), 0)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(hours)h \(String(format: "%02d", remainder))m"
        }
        return "\(remainder)m"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    /// Locale-aware clock time ("5:12 PM" / "17:12") in the given time zone.
    static func time(_ date: Date, timeZone: TimeZone?) -> String {
        timeFormatter.timeZone = timeZone ?? .current
        return timeFormatter.string(from: date)
    }

    /// Compact coordinates for display, e.g. "33.57°N, 7.59°W".
    static func coordinate(_ latitude: Double, _ longitude: Double) -> String {
        let lat = String(format: "%.2f°%@", abs(latitude), latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.2f°%@", abs(longitude), longitude >= 0 ? "E" : "W")
        return "\(lat), \(lon)"
    }
}
