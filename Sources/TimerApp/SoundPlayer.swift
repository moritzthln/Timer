import AppKit

enum SoundPlayer {
    private static var current: NSSound?

    /// Plays the completion chime once at `volume` (0.0–1.0).
    static func playCompletionChime(volume: Double) {
        guard let sound = NSSound(named: "Glass") else { return }
        sound.volume = Float(min(1, max(0, volume)))
        current = sound
        sound.play()
    }
}
