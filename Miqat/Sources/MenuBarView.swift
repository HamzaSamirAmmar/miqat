import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: PrayerScheduleStore
    @ObservedObject var location: LocationManager

    @State private var showsLocationEditor = false
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            if store.place == nil {
                onboarding
            } else {
                scheduleSection

                Divider()

                if showsLocationEditor {
                    locationEditor
                } else {
                    locationRow
                }

                settingsSection
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 330)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Miqat")
                .font(.title3.weight(.semibold))
            Text(Self.dateLine(for: store.now, timeZone: store.displayTimeZone))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "Sep 24, 2026 · Rabiʻ II 13, 1448 AH"
    private static func dateLine(for date: Date, timeZone: TimeZone?) -> String {
        let gregorian = DateFormatter()
        gregorian.dateStyle = .medium
        gregorian.timeStyle = .none
        gregorian.timeZone = timeZone ?? .current

        let hijri = DateFormatter()
        hijri.calendar = Calendar(identifier: .islamicCivil)
        hijri.locale = Locale(identifier: "en")
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
            Image(systemName: isNext ? "arrow.right.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(isNext ? Color.accentColor : .clear)
                .frame(width: 12)

            Text(entry.key.displayName)
                .foregroundStyle(isNext ? .primary : .secondary)

            if isNext {
                Text("in \(Format.remaining(entry.date.timeIntervalSince(store.now)))")
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

    private var locationRow: some View {
        HStack {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(Color.accentColor)
            Text(store.place?.name ?? "—")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Change…") {
                location.clearSearch()
                searchQuery = ""
                showsLocationEditor = true
            }
            .controlSize(.small)
        }
        .font(.callout)
    }

    private var locationEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            locationSearchSection

            manualEntrySection

            HStack {
                detectButton
                Spacer()
                Button("Done") {
                    location.clearSearch()
                    searchQuery = ""
                    showsLocationEditor = false
                }
            }
        }
    }

    private var detectButton: some View {
        Button {
            location.detect()
        } label: {
            Label(location.isLocating ? "Locating…" : "Use My Location", systemImage: "location.fill")
        }
        .disabled(location.isLocating)
    }

    private var locationSearchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search city…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: searchQuery) { query in
                        location.search(query)
                    }
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Text("Offline search — \(CityDatabase.cities.count.formatted()) cities bundled")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let error = location.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(location.searchResults) { city in
                Button {
                    store.place = CityDatabase.place(from: city)
                    location.clearSearch()
                    searchQuery = ""
                    showsLocationEditor = false
                } label: {
                    HStack {
                        Image(systemName: "mappin")
                            .foregroundStyle(Color.accentColor)
                        Text(city.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(city.timeZone?.abbreviation() ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
    }

    /// Fully-offline manual coordinates: the nearest bundled city supplies
    /// the time zone and a "Near …" label unless a custom name is given.
    private var manualEntrySection: some View {
        DisclosureGroup("Enter coordinates manually", isExpanded: $showsManualEntry) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Latitude (e.g. 33.5731)", text: $manualLatitude)
                    TextField("Longitude (e.g. -7.5898)", text: $manualLongitude)
                }
                .textFieldStyle(.roundedBorder)
                .font(.callout)

                TextField("Name (optional)", text: $manualName)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)

                if let manualError {
                    Text(manualError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Use Coordinates") {
                    applyManualCoordinates()
                }
                .disabled(manualLatitude.isEmpty || manualLongitude.isEmpty)
            }
            .padding(.top, 4)
        }
        .font(.callout)
    }

    private func applyManualCoordinates() {
        let latitude = Self.parseCoordinate(manualLatitude)
        let longitude = Self.parseCoordinate(manualLongitude)

        guard let latitude, (-90...90).contains(latitude) else {
            manualError = "Latitude must be a number between -90 and 90."
            return
        }
        guard let longitude, (-180...180).contains(longitude) else {
            manualError = "Longitude must be a number between -180 and 180."
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
        showsLocationEditor = false
    }

    /// Accepts both "." and "," decimal separators.
    private static func parseCoordinate(_ string: String) -> Double? {
        Double(string.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Onboarding (first run, no place yet)

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set your location to see today's prayer times and a live countdown to the next prayer.")
                .font(.callout)
                .foregroundStyle(.secondary)

            detectButton
                .frame(maxWidth: .infinity)

            Text("or search for a city")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)

            locationSearchSection
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Method", selection: $store.method) {
                ForEach(CalculationMethodChoice.allCases) { method in
                    Text(method.displayName).tag(method)
                }
            }

            HStack(spacing: 12) {
                Picker("Asr", selection: $store.madhab) {
                    ForEach(AsrMadhab.allCases) { madhab in
                        Text(madhab.displayName).tag(madhab)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Title", selection: $store.titleStyle) {
                    ForEach(TitleStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .font(.callout)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Start at Login", isOn: loginBinding)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit Miqat")
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
