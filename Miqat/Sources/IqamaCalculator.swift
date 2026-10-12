import Foundation

/// Time remaining until the iqama (إقامة الصلاة) of the prayer that has just
/// been called.
///
/// Iqama times are set locally by each mosque, so no astronomical formula
/// exists; the widely used convention is a fixed gap after the adhan. These
/// defaults follow common Saudi (Umm al-Qura) practice — a longer gap for
/// Fajr, 20 minutes for Dhuhr, Asr and Isha, and a short one for Maghrib.
enum IqamaCalculator {

    /// The prayers that have an iqama (sunrise is not a prayer).
    static let prayers: [PrayerKey] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    /// The range a custom gap may take, in minutes.
    static let gapRange: ClosedRange<Int> = 1...60

    /// Default minutes between the adhan and the iqama, per prayer.
    static func defaultGapMinutes(for prayer: PrayerKey) -> Int? {
        switch prayer {
        case .fajr: return 25
        case .dhuhr: return 20
        case .asr: return 20
        case .maghrib: return 10
        case .isha: return 20
        case .sunrise: return nil // no prayer, so no iqama
        }
    }

    /// The prayer currently between its adhan and its iqama.
    struct Pending: Equatable {
        let prayer: PrayerKey
        let iqama: Date
    }

    /// The pending iqama at `now`, or nil outside any adhan→iqama gap.
    /// `customGaps` overrides the defaults per prayer.
    static func pending(
        today: [PrayerEntry],
        now: Date,
        customGaps: [PrayerKey: Int] = [:]
    ) -> Pending? {
        for entry in today {
            guard let gap = customGaps[entry.key] ?? defaultGapMinutes(for: entry.key) else { continue }
            let iqama = entry.date.addingTimeInterval(TimeInterval(gap * 60))
            if entry.date <= now, now < iqama {
                return Pending(prayer: entry.key, iqama: iqama)
            }
        }
        return nil
    }
}
