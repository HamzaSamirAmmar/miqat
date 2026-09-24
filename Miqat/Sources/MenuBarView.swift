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
    @ObservedObject private var localization = Localization.shared

    @State private var activeScreen: ActiveScreen = .schedule
    @State private var searchQuery = ""
    @State private var showsManualEntry = false
    @State private var manualLatitude = ""
    @State private var manualLongitude = ""
    @State private var manualName = ""
    @State private var manualError: String?

    /// Directional SF Symbols must be picked per layout direction — SwiftUI
    /// does not mirror `chevron.right`-style glyphs on its own.
    private func directionalIcon(ltr: String, rtl: String) -> String {
        localization.isRTL ? rtl : ltr
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.place == nil {
                onboarding
            } else {
                switch activeScreen {
                case .settings:
                    SettingsView(store: store) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeScreen = .schedule
                        }
                    }
                case .locationPicker:
                    locationPicker
                case .schedule:
                    mainScheduleContent
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .environment(\.locale, localization.locale)
        .environment(\.layoutDirection, localization.layoutDirection)
        .onChange(of: store.place) { _ in
            // A place arriving (detect, pick, manual) returns to schedule.
            if activeScreen == .locationPicker, store.place != nil {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeScreen = .schedule
                }
                location.clearSearch()
                searchQuery = ""
            }
        }
    }

    // MARK: - Main Schedule Content

    private var mainScheduleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            PrayerHeroCard(store: store)

            scheduleSection

            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text("Miqat")
                    .font(.title3.weight(.bold))

                Spacer()

                // Location pill button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        location.clearSearch()
                        searchQuery = ""
                        activeScreen = .locationPicker
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(store.place?.flagEmoji ?? "📍")
                            .font(.subheadline)
                        Text(store.place?.name ?? localization.string("location.title"))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: directionalIcon(ltr: "chevron.right", rtl: "chevron.left"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                }
                .buttonStyle(.plain)

                // Settings button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeScreen = .settings
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(localization.string("nav.settings"))
            }

            // Dual Date Line (Gregorian & Hijri)
            HStack(spacing: 6) {
                Text(Self.gregorianDateString(for: store.now, timeZone: store.displayTimeZone))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)

                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(Self.hijriDateString(for: store.now, timeZone: store.displayTimeZone))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private static func gregorianDateString(for date: Date, timeZone: TimeZone?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = timeZone ?? .current
        return formatter.string(from: date)
    }

    private static func hijriDateString(for date: Date, timeZone: TimeZone?) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .islamicCivil)
        formatter.locale = Localization.shared.locale
        formatter.dateStyle = .long
        formatter.timeZone = timeZone ?? .current
        return formatter.string(from: date)
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(localization.string("hero.today"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.top, 2)

            VStack(spacing: 3) {
                ForEach(store.today) { entry in
                    scheduleRow(entry)
                }
            }
        }
    }

    private func scheduleRow(_ entry: PrayerEntry) -> some View {
        let isNext = entry.id == store.next?.id
        let isPassed = !isNext && entry.date < store.now

        return HStack(spacing: 10) {
            Group {
                if isNext {
                    Image(systemName: entry.key.symbolName)
                        .foregroundStyle(Color.accentColor)
                } else if isPassed {
                    Image(systemName: entry.key.symbolName)
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: entry.key.symbolName)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .frame(width: 20)

            Text(entry.key.displayName)
                .font(isNext ? .callout.weight(.semibold) : .callout)
                .foregroundStyle(isNext ? Color.primary : (isPassed ? Color.secondary : Color.primary))

            if isPassed {
                Text(localization.string("prayer.passed"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if isNext {
                Text(localization.string("next.prefix", Format.remaining(entry.date.timeIntervalSince(store.now))))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            Spacer()

            Text(Format.time(entry.date, timeZone: store.displayTimeZone))
                .monospacedDigit()
                .font(isNext ? .callout.weight(.semibold) : .callout)
                .foregroundStyle(isNext ? Color.primary : (isPassed ? Color.secondary.opacity(0.6) : Color.primary))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isNext ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .modifier(HoverHighlight())
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(store.method.displayName) · \(store.madhab.displayName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if let place = store.place {
                Text(place.timeZoneIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Location Picker

    private var locationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Text(localization.string("location.title"))
                    .font(.headline)

                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            location.clearSearch()
                            searchQuery = ""
                            activeScreen = .schedule
                        }
                    } label: {
                        Label(
                            localization.string("location.back"),
                            systemImage: directionalIcon(ltr: "chevron.left", rtl: "chevron.right")
                        )
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
        withAnimation(.easeInOut(duration: 0.2)) {
            activeScreen = .schedule
        }
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
        withAnimation(.easeInOut(duration: 0.2)) {
            activeScreen = .schedule
        }
    }

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
