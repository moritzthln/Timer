import AppKit

enum SoundPlayer {
    /// Plays the completion chime once (system sound, subtle).
    static func playCompletionChime() {
        NSSound(named: "Glass")?.play()
    }
}
