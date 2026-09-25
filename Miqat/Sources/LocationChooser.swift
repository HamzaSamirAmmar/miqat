import AppKit
import SwiftUI

/// The three ways to set a location. The tab that opens first matches how the
/// current place was chosen, and the active one is badged on the current card.
enum LocationMode: CaseIterable, Identifiable {
    case search
    case automatic
    case coordinates

    var id: Self { self }

    init(_ source: Place.Source?) {
        switch source {
        case .detected: self = .automatic
        case .coordinates: self = .coordinates
        case .city, nil: self = .search
        }
    }

    var titleKey: String {
        switch self {
        case .search: return "location.mode.search"
        case .automatic: return "location.mode.auto"
        case .coordinates: return "location.mode.coordinates"
        }
    }

    var systemImage: String {
        switch self {
        case .search: return "magnifyingglass"
        case .automatic: return "location.fill"
        case .coordinates: return "scope"
        }
    }
}

/// Location selection shared by onboarding and the Location screen:
/// current-place card, mode switcher, then the chosen mode's controls.
struct LocationChooser: View {
    @ObservedObject var store: PrayerScheduleStore
    @ObservedObject var location: LocationManager
    /// Onboarding has no place yet, so it hides the current-place card.
    var showsCurrentPlace = true

    @ObservedObject private var localization = Localization.shared
    @State private var mode: LocationMode
    @State private var query = ""
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var customName = ""
    @State private var coordinateError: String?
    @FocusState private var searchFocused: Bool

    init(
        store: PrayerScheduleStore,
        location: LocationManager,
        showsCurrentPlace: Bool = true,
        initialMode: LocationMode? = nil
    ) {
        self.store = store
        self.location = location
        self.showsCurrentPlace = showsCurrentPlace
        _mode = State(initialValue: initialMode ?? LocationMode(store.place?.source))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsCurrentPlace, let place = store.place {
                currentPlaceCard(place)
            }

            modePicker

            Group {
                switch mode {
                case .search: searchPane
                case .automatic: automaticPane
                case .coordinates: coordinatesPane
                }
            }
            .transition(.opacity)
        }
        .font(.callout)
        .onDisappear {
            location.clearSearch()
        }
    }

    // MARK: - Current place

    /// The active place, tinted as "selected", with how it was set
    /// ("Automatic", "City", "Coordinates") on the second line.
    private func currentPlaceCard(_ place: Place) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(place.flagEmoji)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(place.displayName)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    if let source = place.source {
                        let mode = LocationMode(source)
                        Label(localization.string(mode.titleKey), systemImage: mode.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.accent)
                            .fixedSize()
                            .help(localization.string("location.source.help"))
                        Text(verbatim: "·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(Format.coordinate(place.latitude, place.longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Brand.accentFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Brand.accent.opacity(0.35), lineWidth: 1)
        )
        .help(place.timeZoneIdentifier)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string("location.current.accessibility", place.displayName))
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(LocationMode.allCases) { option in
                ModeSegment(
                    title: localization.string(option.titleKey),
                    systemImage: option.systemImage,
                    isSelected: mode == option
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) { mode = option }
                }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localization.string("location.mode.accessibility"))
    }

    // MARK: - Search

    private var searchPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField

            let normalized = SearchText.normalize(query)

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
                    .frame(maxHeight: 232)
                }
            } else if normalized.count >= 2 {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text(localization.string("location.noMatches", query))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(localization.string("location.noMatches.hint"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                searchTips
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(localization.string("location.search"), text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onChange(of: query) { location.search($0) }
                .onSubmit {
                    // Return picks the top match — type "mak⏎" and you're done.
                    if let first = location.searchResults.first {
                        pick(first)
                    }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    location.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string("location.clear"))
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

    /// Empty-state help: what can be searched, with tappable examples in
    /// both languages.
    private var searchTips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("location.search.tip"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(Self.examples, id: \.self) { example in
                    Button(example) { query = example }
                        .buttonStyle(PillButtonStyle())
                        .font(.caption)
                }
            }

            Label(
                localization.string("location.offlineHint", CityDatabase.cities.count.formatted()),
                systemImage: "wifi.slash"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
        .padding(.horizontal, 4)
    }

    private static let examples = ["Makkah", "القاهرة", "Morocco", "سوريا"]

    private func cityRow(_ city: City) -> some View {
        let isCurrent = store.place.map {
            abs($0.latitude - city.latitude) < 0.0001 && abs($0.longitude - city.longitude) < 0.0001
        } ?? false

        return Button {
            pick(city)
        } label: {
            HStack(spacing: 10) {
                Text(city.flagEmoji)
                    .font(.body)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(city.localizedName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(CountryName.localized(city.country))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.accent)
                } else {
                    Text(city.timeZone?.abbreviation() ?? "")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(city.displayName)
    }

    private func pick(_ city: City) {
        store.place = CityDatabase.place(from: city)
    }

    // MARK: - Automatic

    private var automaticPane: some View {
        let isActive = store.place?.source == .detected

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isActive ? "checkmark" : "location.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Brand.accent))

                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.string(isActive ? "location.auto.on" : "location.auto.title"))
                        .fontWeight(.semibold)
                    Text(localization.string("location.auto.body"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error = location.lastError {
                errorLabel(error)
            }

            if location.isAuthorizationDenied {
                Button {
                    Self.openLocationPrivacySettings()
                } label: {
                    Text(localization.string("location.auto.openSettings"))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } else {
                Button {
                    location.detect()
                } label: {
                    HStack(spacing: 6) {
                        if location.isLocating {
                            ProgressView().controlSize(.small)
                        }
                        Text(localization.string(
                            location.isLocating ? "location.locating"
                                : (isActive ? "location.auto.refresh" : "location.detect")
                        ))
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .modifier(ProminentIf(isOn: !isActive))
                .disabled(location.isLocating)
            }

            Label(localization.string("location.detect.subtitle"), systemImage: "wifi")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private static func openLocationPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Coordinates

    private var coordinatesPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                labeledField(localization.string("location.latitude"), text: $latitudeText, placeholder: "33.5138")
                labeledField(localization.string("location.longitude"), text: $longitudeText, placeholder: "36.2765")
            }
            .environment(\.layoutDirection, .leftToRight)
            .onChange(of: latitudeText) { splitPastedPair($0) }

            labeledField(localization.string("location.nameOptional"), text: $customName,
                         placeholder: localization.string("location.name.placeholder"))

            if let coordinateError {
                errorLabel(coordinateError)
            } else if let preview = previewPlace {
                HStack(spacing: 6) {
                    Text(preview.flagEmoji)
                    Text(localization.string("location.coordinates.preview", preview.displayName, preview.timeZoneIdentifier))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            } else {
                Text(localization.string("location.coordinates.tip"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }

            Button {
                applyCoordinates()
            } label: {
                Text(localization.string("location.useCoordinates"))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(latitudeText.isEmpty || longitudeText.isEmpty)
        }
        .onAppear(perform: prefillCoordinates)
    }

    private func labeledField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(applyCoordinates)
                .onChange(of: text.wrappedValue) { _ in coordinateError = nil }
        }
    }

    /// What "Use Coordinates" would set, for the live preview line.
    private var previewPlace: Place? {
        guard let latitude = Self.parseCoordinate(latitudeText, positive: "N", negative: "S"),
              let longitude = Self.parseCoordinate(longitudeText, positive: "E", negative: "W"),
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return CityDatabase.manualPlace(name: customName, latitude: latitude, longitude: longitude)
    }

    private func prefillCoordinates() {
        guard latitudeText.isEmpty, longitudeText.isEmpty,
              let place = store.place, place.source == .coordinates else { return }
        latitudeText = String(format: "%.4f", place.latitude)
        longitudeText = String(format: "%.4f", place.longitude)
        if !place.name.hasPrefix("Near ") {
            customName = place.name
        }
    }

    /// Pasting "33.5138, 36.2765" (as copied from a maps app) into the
    /// latitude field fills both fields.
    private func splitPastedPair(_ text: String) {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard parts.count == 2,
              text.contains(where: \.isWhitespace) || parts.allSatisfy({ $0.contains(".") }),
              Self.parseCoordinate(parts[0], positive: "N", negative: "S") != nil,
              Self.parseCoordinate(parts[1], positive: "E", negative: "W") != nil else { return }
        latitudeText = parts[0]
        longitudeText = parts[1]
    }

    private func applyCoordinates() {
        guard !latitudeText.isEmpty, !longitudeText.isEmpty else { return }
        guard let latitude = Self.parseCoordinate(latitudeText, positive: "N", negative: "S"),
              (-90...90).contains(latitude) else {
            coordinateError = localization.string("error.latitude")
            return
        }
        guard let longitude = Self.parseCoordinate(longitudeText, positive: "E", negative: "W"),
              (-180...180).contains(longitude) else {
            coordinateError = localization.string("error.longitude")
            return
        }

        coordinateError = nil
        store.place = CityDatabase.manualPlace(name: customName, latitude: latitude, longitude: longitude)
    }

    /// Accepts "33.51", "33,51", "-7.6", "33.51°", "33.51 N", "7.6W".
    static func parseCoordinate(_ string: String, positive: Character, negative: Character) -> Double? {
        var text = string.trimmingCharacters(in: .whitespaces)
            .uppercased()
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: ",", with: ".")
        var sign = 1.0
        if let last = text.last, last == positive || last == negative {
            sign = last == negative ? -1 : 1
            text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return Double(text).map { $0 * sign }
    }

    // MARK: - Shared pieces

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.multicolor)
            .fixedSize(horizontal: false, vertical: true)
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
}

// MARK: - Segment

/// One segment of the mode switcher: icon over title, the selected one
/// raised like a native segmented control.
private struct ModeSegment: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    /// White in light mode; a lifted gray in dark, like native segments.
    private static let raisedFill = Color(light: .white, dark: NSColor(white: 1, alpha: 0.14))

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected
                          ? Self.raisedFill
                          : Color.primary.opacity(isHovered ? 0.05 : 0))
                    .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 1, y: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// `.borderedProminent` when on, the default bordered style otherwise.
private struct ProminentIf: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
