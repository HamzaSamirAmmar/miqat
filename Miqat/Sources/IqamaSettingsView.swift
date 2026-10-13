import AppKit
import SwiftUI

/// The iqama screen, opened from Settings: per-prayer gaps after the adhan
/// and the low-time color warning for the menu bar countdown.
struct IqamaSettingsView: View {
    @ObservedObject var store: PrayerScheduleStore
    @ObservedObject private var localization = Localization.shared
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenHeader(title: localization.string("settings.iqama.title"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    gapsSection
                    warningSection
                }
                .padding(.horizontal, 1)
                .padding(.bottom, 2)
            }
            .frame(maxHeight: 470)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Gaps

    private var gapsSection: some View {
        FormSection(title: localization.string("settings.iqama.section.gaps"), systemImage: "timer") {
            VStack(spacing: 0) {
                ForEach(IqamaCalculator.prayers) { prayer in
                    gapRow(prayer)
                }

                HStack {
                    Spacer()
                    Button(localization.string("settings.iqama.reset")) {
                        store.iqamaGaps = [:]
                    }
                    .controlSize(.small)
                    .disabled(store.iqamaGaps.isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    /// One line per prayer: glyph · name · minutes between adhan and iqama.
    private func gapRow(_ prayer: PrayerKey) -> some View {
        let binding = Binding(
            get: { store.iqamaGap(for: prayer) },
            set: { store.setIqamaGap($0, for: prayer) }
        )

        return HStack(spacing: 8) {
            Image(systemName: prayer.symbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AnyShapeStyle(Brand.accent))
                .frame(width: 18)

            Text(prayer.displayName)

            Spacer(minLength: 4)

            minutesLabel(binding.wrappedValue)

            Stepper("", value: binding, in: IqamaCalculator.gapRange)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    // MARK: - Warning

    private var warningSection: some View {
        FormSection(title: localization.string("settings.iqama.section.warning"), systemImage: "exclamationmark.circle") {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        store.iqamaWarningEnabled ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.tertiary)
                    )
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(localization.string("settings.iqama.warning.toggle"))
                    Text(localization.string("settings.iqama.warning.subtitle"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Toggle("", isOn: $store.iqamaWarningEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            FormDivider()

            VStack(spacing: 0) {
                FormRow(title: localization.string("settings.iqama.warning.threshold")) {
                    HStack(spacing: 6) {
                        minutesLabel(store.iqamaWarningMinutes)
                        Stepper(
                            "",
                            value: $store.iqamaWarningMinutes,
                            in: PrayerScheduleStore.IqamaDefaults.warningRange
                        )
                        .labelsHidden()
                    }
                }

                FormDivider()

                FormRow(title: localization.string("settings.iqama.warning.color")) {
                    ColorPicker("", selection: colorBinding, supportsOpacity: false)
                        .labelsHidden()
                }
            }
            .disabled(!store.iqamaWarningEnabled)
            .opacity(store.iqamaWarningEnabled ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.15), value: store.iqamaWarningEnabled)
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: store.iqamaWarningColorHex)) },
            set: { store.iqamaWarningColorHex = NSColor($0).hexString }
        )
    }

    private func minutesLabel(_ minutes: Int) -> some View {
        Text("\(minutes) \(localization.string("settings.reminders.minutes"))")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, alignment: .trailing)
    }
}
