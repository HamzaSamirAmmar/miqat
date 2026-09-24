import AppKit
import SwiftUI

enum ActiveScreen {
    case schedule
    case locationPicker
    case settings
}

struct MenuBarView: View {
    @ObservedObject var store: PrayerScheduleStore
    @ObservedObject var location: LocationManager
    @ObservedObject var adhanPlayer: AdhanPlayer
    @ObservedObject var adhanNotifier: SystemAdhanNotifier
    @ObservedObject private var localization = Localization.shared

    @State private var activeScreen: ActiveScreen = .schedule
    @State private var searchQuery = ""
    @State private var showsManualEntry = false
    @State private var manualLatitude = ""
    @State private var manualLongitude = ""
    @State private var manualName = ""
    @State private var manualError: String?
    @FocusState private var searchFocused: Bool

    init(
        store: PrayerScheduleStore,
        location: LocationManager,
        adhanPlayer: AdhanPlayer,
        adhanNotifier: SystemAdhanNotifier,
        initialScreen: ActiveScreen = .schedule
    ) {
        self.store = store
        self.location = location
        self.adhanPlayer = adhanPlayer
        self.adhanNotifier = adhanNotifier
        _activeScreen = State(initialValue: initialScreen)
    }

    var body: some View {
        Group {
            if store.place == nil {
                onboarding
            } else {
                switch activeScreen {
                case .settings:
                    SettingsView(store: store, player: adhanPlayer, notifier: adhanNotifier) {
                        navigate(to: .schedule)
                    }
                    .transition(.opacity)
                case .locationPicker:
                    locationPicker
                        .transition(.opacity)
                case .schedule:
                    mainScheduleContent
                        .transition(.opacity)
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .tint(Brand.accent)
        .environment(\.locale, localization.locale)
        .environment(\.layoutDirection, localization.layoutDirection)
        .onChange(of: store.place) { _ in
            // A place arriving (detect, pick, manual) returns to schedule.
            if activeScreen == .locationPicker, store.place != nil {
                navigate(to: .schedule)
            }
        }
    }

    private func navigate(to screen: ActiveScreen) {
        withAnimation(.easeInOut(duration: 0.18)) {
            location.clearSearch()
            searchQuery = ""
            activeScreen = screen
        }
    }

    // MARK: - Main Schedule Content

    private var mainScheduleContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            PrayerHeroCard(store: store, onToggleAdhan: toggleAdhan)

            schedule

            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.gregorianDateString(for: store.now, timeZone: store.displayTimeZone))
                    .font(.headline)

                HStack(spacing: 4) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Brand.accent)
                    Text(Self.hijriDateString(for: store.now, timeZone: store.displayTimeZone, offset: store.hijriOffset))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            Button {
                navigate(to: .settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(IconButtonStyle())
            .keyboardShortcut(",", modifiers: .command)
            .help(localization.string("nav.settings"))
            .accessibilityLabel(localization.string("nav.settings"))
        }
    }

    private static func gregorianDateString(for date: Date, timeZone: TimeZone?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.locale
        formatter.timeZone = timeZone ?? .current
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }

    static func hijriDateString(for date: Date, timeZone: TimeZone?, offset: Int = 0) -> String {
        let calendar = Calendar(identifier: .islamicUmmAlQura)
        let adjustedDate = calendar.date(byAdding: .day, value: offset, to: date) ?? date

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Localization.shared.locale
        formatter.dateStyle = .long
        formatter.timeZone = timeZone ?? .current
        return formatter.string(from: adjustedDate)
    }

    // MARK: - Schedule

    private var schedule: some View {
        VStack(spacing: 2) {
            ForEach(store.today) { entry in
                // Match on the full entry (key + date): after Isha the next
                // prayer is *tomorrow's* Fajr, not today's passed one.
                let isNext = entry == store.next
                ScheduleRow(
                    entry: entry,
                    time: Format.time(entry.date, timeZone: store.displayTimeZone),
                    isNext: isNext,
                    isPassed: !isNext && entry.date <= store.now,
                    adhanOn: store.isAdhanEnabled(entry.key),
                    onToggleAdhan: { toggleAdhan(entry.key) }
                )
            }
        }
    }

    /// Quick per-prayer mute from the schedule or hero. Turning a prayer on
    /// while the master switch is off turns the master switch on too —
    /// otherwise the click would appear to do nothing.
    private func toggleAdhan(_ prayer: PrayerKey) {
        guard prayer != .sunrise else { return }
        if store.isAdhanEnabled(prayer) {
            store.adhanPrayers.remove(prayer)
            if adhanPlayer.playingTrackID == store.adhanTrack(for: prayer).id {
                adhanPlayer.stop()
            }
        } else {
            store.adhanPrayers.insert(prayer)
            if !store.adhanEnabled {
                store.adhanEnabled = true
                adhanNotifier.requestAuthorization()
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    navigate(to: .locationPicker)
                } label: {
                    HStack(spacing: 5) {
                        Text(store.place?.flagEmoji ?? "📍")
                            .font(.caption)
                        Text(store.place?.name ?? localization.string("location.title"))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(PillButtonStyle())
                .help(localization.string("location.change"))
                .layoutPriority(1)

                Spacer(minLength: 4)

                Button {
                    navigate(to: .settings)
                } label: {
                    Text(verbatim: "\(store.method.displayName) · \(store.madhab.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .help(localization.string("nav.settings"))
            }

            if let place = store.place,
               place.timeZone.secondsFromGMT(for: store.now) != TimeZone.current.secondsFromGMT(for: store.now) {
                Label(localization.string("footer.localTime", place.name), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Location Picker

    private var locationPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenHeader(title: localization.string("location.title")) {
                navigate(to: .schedule)
            }

            locationChooser

            manualEntrySection
        }
    }

    /// Search field plus either results, or the current place and "detect"
    /// shortcut when nothing is typed. Shared by onboarding and the picker.
    private var locationChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField

            if let error = location.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let trimmed = City.fold(searchQuery.trimmingCharacters(in: .whitespaces))

            if !location.searchResults.isEmpty {
                listContainer {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(location.searchResults) { city in
                                cityRow(city)
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 208)
                }
            } else if trimmed.count >= 2 {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text(localization.string("location.noMatches", searchQuery))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                listContainer {
                    VStack(spacing: 1) {
                        if let place = store.place {
                            currentPlaceRow(place)
                        }
                        detectRow
                    }
                    .padding(4)
                }

                Label(
                    localization.string("location.offlineHint", CityDatabase.cities.count.formatted()),
                    systemImage: "wifi.slash"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
            }
        }
        .font(.callout)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(localization.string("location.search"), text: $searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onChange(of: searchQuery) { query in
                    location.search(query)
                }
                .onSubmit {
                    // Return picks the top match — type "mak⏎" and you're done.
                    if let first = location.searchResults.first {
                        pick(first)
                    }
                }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    location.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(searchFocused ? Brand.accent.opacity(0.7) : Color.primary.opacity(0.08),
                              lineWidth: searchFocused ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: searchFocused)
        .onAppear {
            // The popover's window must be key before focus can land.
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private func listContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }

    private func currentPlaceRow(_ place: Place) -> some View {
        HStack(spacing: 10) {
            Text(place.flagEmoji)
                .font(.body)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                    .lineLimit(1)
                Text(Format.coordinate(place.latitude, place.longitude))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Spacer()
            Label(localization.string("location.selected"), systemImage: "checkmark")
                .font(.caption.weight(.medium))
                .foregroundStyle(Brand.accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var detectRow: some View {
        Button {
            location.detect()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Brand.accent))

                VStack(alignment: .leading, spacing: 1) {
                    Text(localization.string(location.isLocating ? "location.locating" : "location.detect"))
                        .foregroundStyle(Brand.accent)
                        .fontWeight(.medium)
                    Text(localization.string("location.detect.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if location.isLocating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .buttonStyle(RowButtonStyle())
        .disabled(location.isLocating)
    }

    private func cityRow(_ city: City) -> some View {
        Button {
            pick(city)
        } label: {
            HStack(spacing: 10) {
                Text(city.flagEmoji)
                    .font(.body)
                    .frame(width: 26)

                Text(city.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(city.timeZone?.abbreviation() ?? "")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .buttonStyle(RowButtonStyle())
    }

    private func pick(_ city: City) {
        store.place = CityDatabase.place(from: city)
        navigate(to: .schedule)
    }

    private var manualEntrySection: some View {
        DisclosureGroup(isExpanded: $showsManualEntry) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    labeledField(localization.string("location.latitude"), text: $manualLatitude, placeholder: "33.5731")
                    labeledField(localization.string("location.longitude"), text: $manualLongitude, placeholder: "-7.5898")
                }

                labeledField(localization.string("location.nameOptional"), text: $manualName, placeholder: "Dar")

                if let manualError {
                    Label(manualError, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    applyManualCoordinates()
                } label: {
                    Text(localization.string("location.useCoordinates"))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(manualLatitude.isEmpty || manualLongitude.isEmpty)
            }
            .padding(.top, 8)
        } label: {
            Label(localization.string("location.manual"), systemImage: "mappin.and.ellipse")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func labeledField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(applyManualCoordinates)
        }
    }

    private func applyManualCoordinates() {
        guard !manualLatitude.isEmpty, !manualLongitude.isEmpty else { return }
        let latitude = Self.parseCoordinate(manualLatitude)
        let longitude = Self.parseCoordinate(manualLongitude)

        guard let latitude, (-90...90).contains(latitude) else {
            manualError = localization.string("error.latitude")
            return
        }
        guard let longitude, (-180...180).contains(longitude) else {
            manualError = localization.string("error.longitude")
            return
        }

        store.place = CityDatabase.manualPlace(
            name: manualName,
            latitude: latitude,
            longitude: longitude
        )

        manualLatitude = ""
        manualLongitude = ""
        manualName = ""
        manualError = nil
        navigate(to: .schedule)
    }

    private static func parseCoordinate(_ string: String) -> Double? {
        Double(string.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Onboarding (first run, no place yet)

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                BrandMark(size: 48)
                    .padding(.bottom, 2)
                Text(localization.string("welcome.title"))
                    .font(.title3.weight(.bold))
                Text(localization.string("welcome.subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            locationChooser

            manualEntrySection
        }
    }
}

// MARK: - Schedule row

private struct ScheduleRow: View {
    let entry: PrayerEntry
    let time: String
    let isNext: Bool
    let isPassed: Bool
    let adhanOn: Bool
    let onToggleAdhan: () -> Void

    @ObservedObject private var localization = Localization.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.key.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isNext ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.secondary))
                .opacity(isPassed ? 0.6 : 1)
                .frame(width: 20)

            Text(entry.key.displayName)
                .fontWeight(isNext ? .semibold : .regular)

            Spacer(minLength: 8)

            Text(time)
                .fontWeight(isNext ? .semibold : .regular)
                .monospacedDigit()

            adhanButton
        }
        .font(.callout)
        .foregroundStyle(isPassed ? .secondary : .primary)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isNext ? Brand.accentFill : (isHovered ? Color.primary.opacity(0.05) : .clear))
        )
        .overlay(alignment: .leading) {
            if isNext {
                Capsule()
                    .fill(Brand.accent)
                    .frame(width: 3, height: 14)
                    .offset(x: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    /// Sunrise never sounds. Others show a muted bell persistently, and an
    /// active bell on hover — quiet by default, one click to change.
    @ViewBuilder
    private var adhanButton: some View {
        if entry.key == .sunrise {
            Color.clear.frame(width: 22, height: 18)
        } else {
            Button(action: onToggleAdhan) {
                Image(systemName: adhanOn ? "bell.fill" : "bell.slash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(adhanOn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(!adhanOn || isHovered ? 1 : 0)
            .help(localization.string(adhanOn ? "adhan.toggle.on" : "adhan.toggle.off"))
            .accessibilityLabel(localization.string(adhanOn ? "adhan.toggle.on" : "adhan.toggle.off"))
        }
    }

    private var accessibilityText: String {
        var parts = [entry.key.displayName, time]
        if isNext { parts.append(localization.string("schedule.next")) }
        if isPassed { parts.append(localization.string("prayer.passed")) }
        return parts.joined(separator: ", ")
    }
}
