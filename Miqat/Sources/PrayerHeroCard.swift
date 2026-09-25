import SwiftUI

/// The popover's focal point: the next prayer and a live countdown, painted
/// with a sky gradient for the stretch of day leading up to it.
struct PrayerHeroCard: View {
    @ObservedObject var store: PrayerScheduleStore
    @ObservedObject private var localization = Localization.shared
    /// Toggles the adhan for a prayer (handled by the parent, which owns
    /// notification permission).
    var onToggleAdhan: (PrayerKey) -> Void

    var body: some View {
        if let next = store.next {
            card(for: next)
        }
    }

    private func card(for next: PrayerEntry) -> some View {
        let palette = SkyPalette.leading(to: next.key)
        let remaining = next.date.timeIntervalSince(store.now)
        // After Isha the next prayer is tomorrow's Fajr, which isn't in `today`.
        let isTomorrow = !store.today.contains(next)
        let nextTime = Format.time(next.date, timeZone: store.displayTimeZone)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Eyebrow
                HStack(spacing: 5) {
                    Text(localization.string("hero.nextPrayer"))
                    if isTomorrow {
                        Text("·")
                        Text(localization.string("hero.tomorrow"))
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))

                Text(next.key.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .padding(.top, 3)

                Text(Format.clock(remaining))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .numericTransition()
                    .animation(.default, value: Int(remaining))
                    .padding(.top, 1)
                    .environment(\.layoutDirection, .leftToRight) // digits never mirror
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localization.string(
                "hero.accessibility",
                next.key.displayName,
                nextTime,
                Format.remaining(remaining)
            ))

            progressBar
                .padding(.top, 12)

            // Interval endpoints: previous prayer → next prayer.
            HStack(spacing: 6) {
                if let previous = store.previousPrayer {
                    Text(verbatim: "\(previous.key.displayName) \(Format.time(previous.date, timeZone: store.displayTimeZone))")
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer(minLength: 4)

                if next.key != .sunrise {
                    adhanBell(for: next.key)
                }

                Text(nextTime)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.top, 7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [palette.top, palette.bottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Soft glow + oversized celestial glyph as illustration.
                RadialGradient(
                    colors: [.white.opacity(0.16), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 170
                )

                Image(systemName: next.key.symbolName)
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.white)
                    .opacity(0.12)
                    .offset(x: localization.isRTL ? -12 : 12, y: -8)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: palette.bottom.opacity(0.28), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.6), value: next.key)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let width = geo.size.width * CGFloat(store.nextPrayerProgress)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))

                Capsule()
                    .fill(.white)
                    .frame(width: max(width, 5))
                    .shadow(color: .white.opacity(0.5), radius: 3)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private func adhanBell(for prayer: PrayerKey) -> some View {
        let isOn = store.isAdhanEnabled(prayer)
        return Button {
            onToggleAdhan(prayer)
        } label: {
            Image(systemName: isOn ? "bell.fill" : "bell.slash.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(isOn ? 0.9 : 0.6))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(localization.string(isOn ? "adhan.toggle.on" : "adhan.toggle.off"))
        .accessibilityLabel(localization.string(isOn ? "adhan.toggle.on" : "adhan.toggle.off"))
    }
}
