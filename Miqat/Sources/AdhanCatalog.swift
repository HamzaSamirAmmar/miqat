import Foundation

/// One embedded adhan recording.
struct AdhanTrack: Identifiable, Equatable, Hashable {
    /// Stable id — also the bundled resource name (`<id>.mp3`).
    let id: String
    /// Fajr variants add "as-salatu khayrun min an-nawm" and belong to Fajr only.
    let isFajrVariant: Bool

    var displayName: String {
        Localization.shared.string("adhan.track.\(id)")
    }
}

/// The embedded adhan library — the single source of truth for what ships
/// inside the app. Files live in `Resources/Adhan/` and are bundled by both
/// SPM (`.copy("Resources")`) and XcodeGen (`Miqat/Resources` sources).
enum AdhanCatalog {

    static let tracks: [AdhanTrack] = [
        AdhanTrack(id: "makkah-fajr", isFajrVariant: true),
        AdhanTrack(id: "madinah-fajr", isFajrVariant: true),
        AdhanTrack(id: "makkah", isFajrVariant: false),
        AdhanTrack(id: "madinah", isFajrVariant: false),
        AdhanTrack(id: "aqsa", isFajrVariant: false),
        AdhanTrack(id: "alafasy", isFajrVariant: false),
    ]

    static let fajrTracks = tracks.filter(\.isFajrVariant)
    static let standardTracks = tracks.filter { !$0.isFajrVariant }

    static func track(id: String) -> AdhanTrack? {
        tracks.first { $0.id == id }
    }

    /// The tracks offered for a prayer: Fajr only ever sees the Fajr
    /// variants (their wording belongs to Fajr), other prayers only see
    /// standard adhans — the two families are never mixed in one picker.
    static func tracks(for prayer: PrayerKey) -> [AdhanTrack] {
        prayer == .fajr ? fajrTracks : standardTracks
    }

    /// The out-of-the-box track for a prayer.
    static func defaultTrack(for prayer: PrayerKey) -> AdhanTrack {
        if prayer == .fajr, let fajr = track(id: "makkah-fajr") {
            return fajr
        }
        return track(id: "makkah") ?? standardTracks[0]
    }

    /// Bundled file URL for a track. SPM keeps the `Resources/` folder
    /// hierarchy; the XcodeGen app bundle flattens resources to the root.
    static func url(for track: AdhanTrack) -> URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        return bundle.url(forResource: track.id, withExtension: "mp3", subdirectory: "Resources/Adhan")
            ?? bundle.url(forResource: track.id, withExtension: "mp3", subdirectory: "Adhan")
            ?? bundle.url(forResource: track.id, withExtension: "mp3")
        #else
        return Bundle.main.url(forResource: track.id, withExtension: "mp3")
        #endif
    }
}
