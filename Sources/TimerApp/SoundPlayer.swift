import AppKit

enum SoundPlayer {
    /// v7: 4 chimes at 1.3 s intervals stretch the alarm to roughly five
    /// seconds instead of one short ping.
    private static let chimeCount = 4
    private static let chimeInterval: TimeInterval = 1.3

    private static var current: NSSound?
    private static var sequenceTimer: Foundation.Timer?
    private static var remainingChimes = 0

    /// Starts the ~5 s alarm sequence at `volume` (0.0–1.0, same volume for
    /// every chime). A new call cancels a still-running previous sequence.
    static func playCompletionChime(volume: Double) {
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        let clamped = Float(min(1, max(0, volume)))
        remainingChimes = chimeCount - 1
        playOnce(volume: clamped)
        let timer = Foundation.Timer(timeInterval: chimeInterval, repeats: true) { timer in
            playOnce(volume: clamped)
            remainingChimes -= 1
            if remainingChimes <= 0 {
                timer.invalidate()
                sequenceTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sequenceTimer = timer
    }

    /// One chime strike; a fresh NSSound per strike lets a still-ringing
    /// tail overlap the next one.
    private static func playOnce(volume: Float) {
        guard let sound = NSSound(named: "Glass") else { return }
        sound.volume = volume
        current = sound
        sound.play()
    }
}
