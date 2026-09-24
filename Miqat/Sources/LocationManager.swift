import CoreLocation
import Foundation

/// One-shot location detection and city search.
///
/// City search runs entirely against the bundled `CityDatabase` — offline and
/// instant. CoreLocation is only used for the optional "Use My Location" fix
/// (Macs locate via Wi-Fi positioning, which needs internet); when the
/// geocoder can't name the fix offline, the nearest bundled city does.
final class LocationManager: NSObject, ObservableObject {

    /// Called with the detected place once a one-shot fix resolves.
    var onPlaceDetected: ((Place) -> Void)?

    @Published private(set) var isLocating = false
    @Published private(set) var searchResults: [City] = []
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
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

    // MARK: - City search (offline, bundled database)

    func search(_ query: String) {
        lastError = nil
        searchResults = CityDatabase.search(query)
    }

    func clearSearch() {
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

                // Geocoder wins when reachable (exact locality name). Offline,
                // the nearest bundled city names the place and supplies the
                // time zone — detection still works without internet.
                if let geocoded = placemarks?.first.flatMap(Self.place(from:)) {
                    self.onPlaceDetected?(geocoded)
                } else {
                    if let error {
                        NSLog("Miqat: reverse geocode failed — \(error.localizedDescription)")
                    }
                    self.onPlaceDetected?(
                        CityDatabase.nearestCityPlace(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                    )
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        lastError = Self.message(for: error)
    }
}

// MARK: - Helpers

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

    static func message(for error: Error) -> String {
        switch (error as? CLError)?.code {
        case .network:
            // Macs locate themselves via Wi-Fi positioning, which queries
            // Apple's database online — so even the fix needs internet.
            return "Network unavailable — Macs locate via Wi-Fi positioning, which needs an internet connection. Try again once you're online."
        case .denied:
            return "Location access was denied — search for a city instead."
        default:
            return error.localizedDescription
        }
    }
}
