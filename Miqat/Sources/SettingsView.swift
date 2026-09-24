import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: PrayerScheduleStore
    @ObservedObject var player: AdhanPlayer
    @ObservedObject var notifier: SystemAdhanNotifier
    @ObservedObject private var localization = Localization.shared
    var onDismiss: () -> Void

    /// Mirrors the login item so the switch redraws after toggling.
    @State private var startsAtLogin = LoginItemManager.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenHeader(title: localization.string("settings.title"), onBack: onDismiss)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    adhanSection
                    calculationSection
                    appearanceSection
                    generalSection
                    aboutSection
                }
                .padding(.horizontal, 1)
                .padding(.bottom, 2)
            }
            .frame(maxHeight: 470)
        }
    }

    // MARK: - Adhan

    /// The five prayers that can sound an adhan (sunrise never does).
    private static let adhanPrayers: [PrayerKey] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    private var adhanSection: some View {
        FormSection(title: localization.string("settings.section.adhan"), systemImage: "speaker.wave.2.fill") {
            FormRow(
                title: localization.string("settings.adhan.master"),
                subtitle: localization.string("settings.adhan.subtitle")
            ) {
                Toggle("", isOn: $store.adhanEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .onChange(of: store.adhanEnabled) { enabled in
                if enabled {
                    // Ask (or re-ask) for banner rights the
                    // moment notifications get switched on.
                    notifier.requestAuthorization()
                } else {
                    player.stop()
                }
            }

            if store.adhanEnabled, notifier.supportsBanners, !notifier.bannersAllowed {
                bannersOffHint
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            FormDivider()

            VStack(spacing: 0) {
                ForEach(Self.adhanPrayers) { prayer in
                    adhanRow(prayer)
                }
            }
            .padding(.vertical, 4)
            .disabled(!store.adhanEnabled)
            .opacity(store.adhanEnabled ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.15), value: store.adhanEnabled)
        }
    }

    /// Shown when macOS isn't letting Miqat show banners. The adhan sound
    /// works regardless — only the banner needs system permission.
    private var bannersOffHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bell.badge.slash.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(localization.string("adhan.banners.denied"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(localization.string("adhan.banners.openSettings")) {
                    notifier.openSystemSettings()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .onAppear {
            // The user may have just granted permission in System Settings.
            notifier.refreshAuthorizationStatus()
        }
    }

    /// One line per prayer: glyph · name · recording menu · preview · switch.
    private func adhanRow(_ prayer: PrayerKey) -> some View {
        let isOn = store.adhanPrayers.contains(prayer)

        return HStack(spacing: 8) {
            Image(systemName: prayer.symbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.tertiary))
                .frame(width: 18)

            Text(prayer.displayName)
                .frame(minWidth: 52, alignment: .leading)

            Spacer(minLength: 4)

            trackMenu(prayer)
                .disabled(!isOn)
                .opacity(isOn ? 1 : 0.5)

            previewButton(prayer)
                .disabled(!isOn)

            Toggle("", isOn: adhanEnabledBinding(prayer))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func adhanEnabledBinding(_ prayer: PrayerKey) -> Binding<Bool> {
        Binding(
            get: { store.adhanPrayers.contains(prayer) },
            set: { enabled in
                if enabled {
                    store.adhanPrayers.insert(prayer)
                } else {
                    store.adhanPrayers.remove(prayer)
                    // Silencing a prayer silences its preview too.
                    if player.playingTrackID == store.adhanTrack(for: prayer).id {
                        player.stop()
                    }
                }
            }
        )
    }

    /// Compact borderless menu — reads as text, so five rows stay calm.
    private func trackMenu(_ prayer: PrayerKey) -> some View {
        let selected = store.adhanTrack(for: prayer)
        return Menu {
            // Fajr only ever sees Fajr-variant recordings; the other prayers
            // only see standard ones — the two families never mix.
            ForEach(AdhanCatalog.tracks(for: prayer)) { track in
                Button {
                    if player.playingTrackID == selected.id {
                        player.stop()
                    }
                    store.adhanTracks[prayer] = track.id
                } label: {
                    if track == selected {
                        Label(track.displayName, systemImage: "checkmark")
                    } else {
                        Text(track.displayName)
                    }
                }
            }
        } label: {
            Text(selected.displayName)
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .tint(.secondary)
        .fixedSize()
        .frame(maxWidth: 138, alignment: .trailing)
    }

    private func previewButton(_ prayer: PrayerKey) -> some View {
        let track = store.adhanTrack(for: prayer)
        let isPlaying = player.playingTrackID == track.id

        return Button {
            if isPlaying {
                player.stop()
            } else {
                player.play(trackID: track.id)
            }
        } label: {
            Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(isPlaying ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(localization.string(isPlaying ? "adhan.preview.stop" : "adhan.preview.play"))
        .accessibilityLabel(localization.string(isPlaying ? "adhan.preview.stop" : "adhan.preview.play"))
    }

    // MARK: - Calculation

    private var calculationSection: some View {
        FormSection(title: localization.string("settings.section.calculation"), systemImage: "function") {
            FormRow(title: localization.string("settings.method")) {
                Picker("", selection: $store.method) {
                    ForEach(CalculationMethodChoice.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: 190, alignment: .trailing)
            }

            FormDivider()

            FormRow(title: localization.string("settings.asr")) {
                Picker("", selection: $store.madhab) {
                    ForEach(AsrMadhab.allCases) { madhab in
                        Text(madhab.displayName).tag(madhab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            FormDivider()

            FormRow(
                title: localization.string("settings.hijriOffset"),
                subtitle: MenuBarView.hijriDateString(
                    for: store.now,
                    timeZone: store.displayTimeZone,
                    offset: store.hijriOffset
                )
            ) {
                HStack(spacing: 6) {
                    Text(hijriOffsetDisplay)
                        .monospacedDigit()
                        .foregroundStyle(store.hijriOffset == 0 ? .secondary : .primary)
                        .frame(minWidth: 18, alignment: .trailing)
                        .environment(\.layoutDirection, .leftToRight)
                    Stepper("", value: $store.hijriOffset, in: -2...2)
                        .labelsHidden()
                }
            }
            .help(localization.string("settings.hijriOffset.hint"))
        }
    }

    private var hijriOffsetDisplay: String {
        store.hijriOffset > 0 ? "+\(store.hijriOffset)" : "\(store.hijriOffset)"
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        FormSection(title: localization.string("settings.section.appearance"), systemImage: "menubar.rectangle") {
            VStack(spacing: 10) {
                Picker("", selection: $store.titleStyle) {
                    ForEach(TitleStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                menuBarPreview
            }
            .padding(10)
        }
    }

    /// A miniature menu bar showing exactly what the chosen style renders.
    private var menuBarPreview: some View {
        let next = store.next
        let countdown = next.map { Format.countdown($0.date.timeIntervalSince(store.now)) } ?? "–:–"
        let title: String
        switch store.titleStyle {
        case .icon: title = ""
        case .countdown: title = countdown
        case .labeled: title = "\(next?.key.displayName ?? "") \(countdown)"
        }

        return HStack(spacing: 14) {
            Image(systemName: "wifi")
            Image(systemName: "battery.75")

            HStack(spacing: 5) {
                if store.titleStyle == .icon {
                    Image(nsImage: MenuBarIcon.image)
                        .renderingMode(.template)
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, design: .monospaced))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))

            Image(systemName: "switch.2")
        }
        .font(.system(size: 12))
        .foregroundStyle(.primary.opacity(0.85))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.bar)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .environment(\.layoutDirection, .leftToRight) // the menu bar never mirrors
        .animation(.easeInOut(duration: 0.15), value: store.titleStyle)
        .accessibilityLabel(localization.string("settings.menubar.preview"))
    }

    // MARK: - General

    private var generalSection: some View {
        FormSection(title: localization.string("settings.section.general"), systemImage: "gearshape") {
            FormRow(title: localization.string("settings.language")) {
                Picker("", selection: $localization.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            FormDivider()

            FormRow(title: localization.string("settings.login")) {
                Toggle("", isOn: $startsAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: startsAtLogin) { enabled in
                        _ = LoginItemManager.setEnabled(enabled)
                        // Reflect the real state if registration failed.
                        startsAtLogin = LoginItemManager.isEnabled
                    }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BrandMark(size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Miqat")
                        .font(.headline)
                    Text(localization.string("settings.version", versionString))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text(localization.string("settings.quit"))
                }
                .controlSize(.small)
                .keyboardShortcut("q", modifiers: .command)
            }

            Label(localization.string("settings.offlineNote"), systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
