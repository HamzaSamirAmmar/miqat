import AppKit
import Foundation

/// Anything that can start/stop adhan playback. Lets the scheduler and its
/// tests work without touching real audio.
protocol AdhanPlaying: AnyObject {
    /// Plays a track, replacing anything already playing.
    func play(trackID: String)
    func stop()
}

/// Plays bundled adhan recordings via `NSSound` — the lightest way to play
/// a file on macOS, with no audio-session management to worry about.
final class AdhanPlayer: NSObject, ObservableObject, AdhanPlaying {

    /// The track currently playing, for UI play/stop state.
    @Published private(set) var playingTrackID: String?

    private var sound: NSSound?

    /// Plays the track from its start, stopping whatever was playing before.
    func play(trackID: String) {
        guard let track = AdhanCatalog.track(id: trackID),
              let url = AdhanCatalog.url(for: track) else {
            NSLog("Miqat: adhan track not found in bundle — \(trackID)")
            return
        }

        let sound = NSSound(contentsOf: url, byReference: true)
        guard let sound else {
            NSLog("Miqat: adhan track failed to load — \(trackID)")
            return
        }

        stop()
        sound.delegate = self
        self.sound = sound
        playingTrackID = trackID
        sound.play()
    }

    func stop() {
        sound?.stop()
        sound = nil
        playingTrackID = nil
    }
}

extension AdhanPlayer: NSSoundDelegate {
    /// Clears the playing state when the recording finishes on its own.
    func sound(_ sound: NSSound, didFinishPlaying successfully: Bool) {
        guard sound === self.sound else { return }
        self.sound = nil
        playingTrackID = nil
    }
}
