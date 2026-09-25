import CoreLocation
import Foundation

/// One-shot location detection and city search.
///
/// City search runs entirely against the bundled `CityDatabase` — offline and
/// instant. CoreLocation is only used for the "Automatic" mode fix (Macs
/// locate via Wi-Fi positioning, which needs internet); when the geocoder
/// can't name the fix offline, the nearest bundled city does.
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
    /// Background refresh (launch / wake): no prompts, no error messages.
    private var isSilent = false

    override init() {
        super.init()
        manager.delegate = self
        // City-level accuracy is plenty for prayer times and resolves fast.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - Auto-detect

    func detect() {
        isSilent = false
        lastError = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            awaitingAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startFix()
        default:
            lastError = Localization.shared.string("error.deniedSettings")
        }
    }

    /// Re-detects in the background for places in Automatic mode — only when
    /// access was already granted, and failures stay quiet (the last known
    /// place simply remains).
    func refreshSilently() {
        guard !isLocating else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isSilent = true
            startFix()
        default:
            break
        }
    }

    private func startFix() {
        isLocating = true
        manager.requestLocation()
    }

    // MARK: - City search (offline, bundled database)

    var isAuthorizationDenied: Bool {
        [.denied, .restricted].contains(manager.authorizationStatus)
    }

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
            lastError = Localization.shared.string("error.denied")
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        isLocating = false

        // English first, then Arabic, so the name follows the UI language.
        // Geocoder wins when reachable (exact locality name). Offline, the
        // nearest bundled city names the place and supplies the time zone —
        // detection still works without internet.
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")) { [weak self] placemarks, error in
            guard let self else { return }
            guard let english = placemarks?.first, english.location != nil else {
                if let error {
                    NSLog("Miqat: reverse geocode failed — \(error.localizedDescription)")
                }
                DispatchQueue.main.async {
                    self.onPlaceDetected?(
                        CityDatabase.nearestCityPlace(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                    )
                }
                return
            }

            self.geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ar")) { placemarks, _ in
                DispatchQueue.main.async {
                    self.onPlaceDetected?(Self.place(english: english, arabic: placemarks?.first, fix: location))
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        guard !isSilent else { return }
        lastError = Self.message(for: error)
    }
}

// MARK: - Helpers

private extension LocationManager {

    static func place(english: CLPlacemark, arabic: CLPlacemark?, fix: CLLocation) -> Place {
        func label(_ placemark: CLPlacemark, fallback: String, separator: String) -> String {
            let locality = placemark.locality ?? placemark.name ?? fallback
            let country = placemark.country ?? placemark.isoCountryCode ?? ""
            return [locality, country].filter { !$0.isEmpty }.joined(separator: separator)
        }

        return Place(
            name: label(english, fallback: "Current location", separator: ", "),
            arabicName: arabic.map { label($0, fallback: "الموقع الحالي", separator: "، ") },
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            timeZoneIdentifier: (english.timeZone ?? .current).identifier,
            countryCode: english.isoCountryCode,
            source: .detected
        )
    }

    static func message(for error: Error) -> String {
        switch (error as? CLError)?.code {
        case .network:
            // Macs locate themselves via Wi-Fi positioning, which queries
            // Apple's database online — so even the fix needs internet.
            Localization.shared.string("error.network")
        case .denied:
            Localization.shared.string("error.denied")
        default:
            error.localizedDescription
        }
    }
}
