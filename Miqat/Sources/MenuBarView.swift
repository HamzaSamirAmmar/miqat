import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: PrayerScheduleStore
    @ObservedObject var location: LocationManager
    @ObservedObject private var localization = Localization.shared

    @State private var showingLocationPicker = false
    @State private var searchQuery = ""
    @State private var showsManualEntry = false
    @State private var manualLatitude = ""
    @State private var manualLongitude = ""
    @State private var manualName = ""
    @State private var manualError: String?

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { LoginItemManager.isEnabled },
            set: { enabled in
                _ = LoginItemManager.setEnabled(enabled)
            }
        )
    }

    /// Directional SF Symbols must be picked per layout direction — SwiftUI
    /// does not mirror `chevron.right`-style glyphs on its own.
    private func directionalIcon(ltr: String, rtl: String) -> String {
        localization.isRTL ? rtl : ltr
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            if store.place == nil {
                onboarding
            } else if showingLocationPicker {
                locationPicker
            } else {
                scheduleSection

                Divider()

                locationCard
                settingsSection
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 340)
        .environment(\.locale, localization.locale)
        .environment(\.layoutDirection, localization.layoutDirection)
        .onChange(of: store.place) { _ in
            // A place arriving (detect, pick, manual) closes the picker.
            if showingLocationPicker, store.place != nil {
                showingLocationPicker = false
                location.clearSearch()
                searchQuery = ""
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Miqat")
                .font(.title3.weight(.semibold))
            Text(Self.dateLine(for: store.now, timeZone: store.displayTimeZone))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// "Sep 24, 2026 · Rabiʻ II 13, 1448 AH" (Arabic: "٢٤ سبتمبر ٢٠٢٦ · ١٤ ربيع الآخر ١٤٤٨ هـ")
    private static func dateLine(for date: Date, timeZone: TimeZone?) -> String {
        let locale = Localization.shared.locale

        let gregorian = DateFormatter()
        gregorian.locale = locale
        gregorian.dateStyle = .medium
        gregorian.timeStyle = .none
        gregorian.timeZone = timeZone ?? .current

        let hijri = DateFormatter()
        hijri.calendar = Calendar(identifier: .islamicCivil)
        hijri.locale = locale
        hijri.dateStyle = .long
        hijri.timeZone = timeZone ?? .current

        return "\(gregorian.string(from: date)) · \(hijri.string(from: date))"
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(spacing: 6) {
            ForEach(store.today) { entry in
                scheduleRow(entry)
            }
        }
    }

    private func scheduleRow(_ entry: PrayerEntry) -> some View {
        let isNext = entry.id == store.next?.id

        return HStack(spacing: 6) {
            Image(systemName: isNext
                  ? directionalIcon(ltr: "arrow.right.circle.fill", rtl: "arrow.left.circle.fill")
                  : "circle")
                .font(.caption2)
                .foregroundStyle(isNext ? Color.accentColor : .clear)
                .frame(width: 12)

            Text(entry.key.displayName)
                .foregroundStyle(isNext ? .primary : .secondary)

            if isNext {
                Text(localization.string("next.prefix", Format.remaining(entry.date.timeIntervalSince(store.now))))
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            Text(Format.time(entry.date, timeZone: store.displayTimeZone))
                .monospacedDigit()
                .foregroundStyle(isNext ? .primary : .secondary)
        }
        .font(isNext ? .callout.weight(.semibold) : .callout)
    }

    // MARK: - Location

    /// Compact summary card on the main panel — tap to open the picker.
    private var locationCard: some View {
        Button {
            location.clearSearch()
            searchQuery = ""
            showingLocationPicker = true
        } label: {
            HStack(spacing: 10) {
                Text(store.place?.flagEmoji ?? "📍")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.place?.name ?? "Set location")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let place = store.place {
                        Text("\(place.timeZoneIdentifier) · \(Format.coordinate(place.latitude, place.longitude))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                Image(systemName: directionalIcon(ltr: "chevron.right", rtl: "chevron.left"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Full-popover location picker: offline search, detect, or manual
    /// coordinates — gets the whole popover instead of a cramped strip.
    private var locationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Text(localization.string("location.title"))
                    .font(.headline)

                HStack {
                    Button {
                        location.clearSearch()
                        searchQuery = ""
                        showingLocationPicker = false
                    } label: {
                        Label(localization.string("location.back"),
                              systemImage: directionalIcon(ltr: "chevron.left", rtl: "chevron.right"))
                    }
                    .controlSize(.small)
                    Spacer()
                }
            }

            locationSearchSection

            detectButton

            manualEntrySection
        }
    }

    private var detectButton: some View {
        Button {
            location.detect()
        } label: {
            HStack(spacing: 8) {
                if location.isLocating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "location.fill")
                }
                Text(localization.string(location.isLocating ? "location.locating" : "location.detect"))
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .disabled(location.isLocating)
    }

    private var locationSearchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(localization.string("location.search"), text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: searchQuery) { query in
                        location.search(query)
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
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            if let error = location.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !location.searchResults.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(location.searchResults) { city in
                            cityRow(city)
                        }
                    }
                    .padding(3)
                }
                .frame(maxHeight: 196)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else if City.fold(searchQuery.trimmingCharacters(in: .whitespaces)).count >= 2 {
                Text(localization.string("location.noMatches", searchQuery))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                Text(localization.string("location.offlineHint", CityDatabase.cities.count.formatted()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
    }

    private func cityRow(_ city: City) -> some View {
        Button {
            pick(city)
        } label: {
            HStack(spacing: 10) {
                Text(city.flagEmoji)
                    .font(.body)

                Text(city.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(city.timeZone?.abbreviation() ?? "")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HoverHighlight())
    }

    private func pick(_ city: City) {
        store.place = CityDatabase.place(from: city)
        location.clearSearch()
        searchQuery = ""
        showingLocationPicker = false
    }

    /// Fully-offline manual coordinates: the nearest bundled city supplies
    /// the time zone and a "Near …" label unless a custom name is given.
    private var manualEntrySection: some View {
        DisclosureGroup(isExpanded: $showsManualEntry) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    labeledField(localization.string("location.latitude"), text: $manualLatitude, placeholder: "33.5731")
                    labeledField(localization.string("location.longitude"), text: $manualLongitude, placeholder: "-7.5898")
                }

                labeledField(localization.string("location.nameOptional"), text: $manualName, placeholder: "Dar")

                if let manualError {
                    Text(manualError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    applyManualCoordinates()
                } label: {
                    Text(localization.string("location.useCoordinates"))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .disabled(manualLatitude.isEmpty || manualLongitude.isEmpty)
            }
            .padding(.top, 6)
        } label: {
            Label(localization.string("location.manual"), systemImage: "mappin.and.ellipse")
        }
        .font(.callout)
    }

    private func labeledField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func applyManualCoordinates() {
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
        location.clearSearch()
        searchQuery = ""
        showingLocationPicker = false
    }

    /// Accepts both "." and "," decimal separators.
    private static func parseCoordinate(_ string: String) -> Double? {
        Double(string.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Onboarding (first run, no place yet)

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🕌")
                    .font(.system(size: 30))
                Text(localization.string("welcome.title"))
                    .font(.headline)
                Text(localization.string("welcome.subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            locationSearchSection

            orDivider

            detectButton

            manualEntrySection
        }
    }

    private var orDivider: some View {
        HStack(spacing: 8) {
            Divider()
            Text(localization.string("onboarding.or"))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Divider()
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(localization.string("settings.language"), selection: $localization.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }

            Picker(localization.string("settings.method"), selection: $store.method) {
                ForEach(CalculationMethodChoice.allCases) { method in
                    Text(method.displayName).tag(method)
                }
            }

            // Full-width segmented rows — side-by-side segments overflow the
            // popover once Arabic labels (شافعي/حنفي · عدّ تنازلي) get involved.
            Picker(localization.string("settings.asr"), selection: $store.madhab) {
                ForEach(AsrMadhab.allCases) { madhab in
                    Text(madhab.displayName).tag(madhab)
                }
            }
            .pickerStyle(.segmented)

            Picker(localization.string("settings.menubar"), selection: $store.titleStyle) {
                ForEach(TitleStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
        }
        .font(.callout)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(localization.string("settings.login"), isOn: loginBinding)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Text(localization.string("settings.quit"))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            Text("Miqat \(Self.versionString)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }

    private static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

/// Soft row highlight on hover, echoing the native list feel.
private struct HoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}
