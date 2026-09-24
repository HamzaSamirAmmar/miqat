import SwiftUI

struct PrayerHeroCard: View {
    @ObservedObject var store: PrayerScheduleStore
    @ObservedObject private var localization = Localization.shared

    var body: some View {
        if let next = store.next {
            VStack(alignment: .leading, spacing: 10) {
                // Top row: "Next Prayer" header and exact target time
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkle")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text(localization.string("hero.nextPrayer"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(Format.time(next.date, timeZone: store.displayTimeZone))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                // Main row: Prayer name + celestial symbol, and prominent countdown badge
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: next.key.symbolName)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)

                    Text(next.key.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(localization.string("next.prefix", Format.remaining(next.date.timeIntervalSince(store.now))))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }

                // Sleek progress bar
                GeometryReader { geo in
                    ZStack(alignment: localization.isRTL ? .trailing : .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4)

                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(geo.size.width * CGFloat(store.nextPrayerProgress), 4), height: 4)
                    }
                }
                .frame(height: 4)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.10),
                                Color.accentColor.opacity(0.03),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
            )
        }
    }
}
