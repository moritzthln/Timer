import AppKit

enum SoundPlayer {
    private static var current: NSSound?
    private static var sequenceTimer: Foundation.Timer?
    private static var remainingChimes = 0

    /// ~5 s bell swell (bundled alarm-major.caf): single-timer finish and
    /// focus-phase end.
    static func playMajorAlarm(volume: Double) {
        play(file: "alarm-major", volume: volume)
    }

    /// ~1.5 s soft tone (bundled chime-minor.caf): break end — noticeable,
    /// not startling.
    static func playMinorChime(volume: Double) {
        play(file: "chime-minor", volume: volume)
    }

    // MARK: - Playback

    /// Bundled sound at Contents/Resources/Sounds/<name>.caf, nil if absent
    /// (e.g. bare `swift run` binary without the app bundle).
    private static func soundURL(_ name: String) -> URL? {
        guard let base = Bundle.main.resourceURL else { return nil }
        let url = base.appendingPathComponent("Sounds/\(name).caf")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A new alarm always replaces a still-playing one.
    private static func play(file: String, volume: Double) {
        stopCurrent()
        guard let url = soundURL(file),
              let sound = NSSound(contentsOf: url, byReference: true) else {
            playGlassFallback(volume: volume) // missing file — never silent
            return
        }
        sound.volume = Float(min(1, max(0, volume)))
        current = sound
        sound.play()
    }

    private static func stopCurrent() {
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        current?.stop()
        current = nil
    }

    // MARK: - Fallback (v7 behavior)

    private static let fallbackChimeCount = 4
    private static let fallbackChimeInterval: TimeInterval = 1.3

    /// 4× Glass at 1.3 s intervals — the v7 alarm, kept only for the case
    /// that the bundled .caf files are missing.
    private static func playGlassFallback(volume: Double) {
        let clamped = Float(min(1, max(0, volume)))
        remainingChimes = fallbackChimeCount - 1
        playGlassOnce(volume: clamped)
        let timer = Foundation.Timer(timeInterval: fallbackChimeInterval, repeats: true) { timer in
            playGlassOnce(volume: clamped)
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
    private static func playGlassOnce(volume: Float) {
        guard let sound = NSSound(named: "Glass") else { return }
        sound.volume = volume
        current = sound
        sound.play()
    }
}
