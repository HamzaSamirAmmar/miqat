import CoreLocation
import Foundation

/// One-shot location detection and city search, both via system services.
///
/// CoreLocation provides the fix; CLGeocoder turns coordinates ↔ city names.
/// Computation of prayer times happens locally — nothing leaves the Mac except
/// the geocoder's own lookup request.
final class LocationManager: NSObject, ObservableObject {

    /// Called with the detected place once a one-shot fix resolves.
    var onPlaceDetected: ((Place) -> Void)?

    @Published private(set) var isLocating = false
    @Published private(set) var isSearching = false
    @Published private(set) var searchResults: [Place] = []
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var searchDebounce: DispatchWorkItem?
    /// True while waiting for the user to answer the permission prompt.
    private var awaitingAuthorization = false

    override init() {
        super.init()
        manager.delegate = self
        // City-level accuracy is plenty for prayer times and resolves fast.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - Auto-detect

    func detect() {
        lastError = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            awaitingAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startFix()
        default:
            lastError = "Location access is denied — search for a city instead. You can change this in System Settings › Privacy & Security › Location Services."
        }
    }

    private func startFix() {
        isLocating = true
        manager.requestLocation()
    }

    // MARK: - City search

    /// Debounced forward geocoding; fires ~300 ms after typing settles.
    func search(_ query: String) {
        searchDebounce?.cancel()
        lastError = nil

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.performSearch(trimmed)
        }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func performSearch(_ query: String) {
        isSearching = true
        geocoder.geocodeAddressString(query) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSearching = false

                if let error {
                    self.searchResults = []
                    self.lastError = Self.message(for: error)
                    return
                }

                self.searchResults = (placemarks ?? []).compactMap(Self.place(from:))
                if self.searchResults.isEmpty {
                    self.lastError = "No cities found for “\(query)”."
                }
            }
        }
    }

    func clearSearch() {
        searchDebounce?.cancel()
        searchDebounce = nil
        isSearching = false
        searchResults = []
        lastError = nil
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard awaitingAuthorization else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            awaitingAuthorization = false
            startFix()
        case .denied, .restricted:
            awaitingAuthorization = false
            isLocating = false
            lastError = "Location access was denied — search for a city instead."
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        isLocating = false

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }

                // A geocoding failure still leaves a perfectly usable place:
                // raw coordinates plus the system time zone.
                if let error {
                    NSLog("Miqat: reverse geocode failed — \(error.localizedDescription)")
                }
                let detected = placemarks?.first.flatMap(Self.place(from:)) ?? Self.fallbackPlace(for: location)
                self.onPlaceDetected?(detected)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        lastError = Self.message(for: error)
    }
}

// MARK: - Place construction

private extension LocationManager {

    static func place(from placemark: CLPlacemark) -> Place? {
        guard let location = placemark.location else { return nil }

        let locality = placemark.locality ?? placemark.name ?? "Current location"
        let country = placemark.country ?? placemark.isoCountryCode ?? ""
        let name = [locality, country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        return Place(
            name: name.isEmpty ? "Current location" : name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeZoneIdentifier: (placemark.timeZone ?? .current).identifier
        )
    }

    static func fallbackPlace(for location: CLLocation) -> Place {
        Place(
            name: "Current location",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeZoneIdentifier: TimeZone.current.identifier
        )
    }

    static func message(for error: Error) -> String {
        switch (error as? CLError)?.code {
        case .network:
            return "Network unavailable — city search needs an internet connection."
        case .denied:
            return "Location access was denied — search for a city instead."
        default:
            return error.localizedDescription
        }
    }
}
