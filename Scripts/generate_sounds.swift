import AVFoundation
import Foundation

// Generates the bundled alarm sounds by rendering sine partials with an
// attack/sustain/exponential-decay envelope through an offline AVAudioEngine
// into .caf files (44.1 kHz mono float32). Run once, commit the output:
//   swift Scripts/generate_sounds.swift Resources/Sounds

struct Partial {
    let frequency: Double
    let amplitude: Double
}

struct SoundSpec {
    let filename: String
    let duration: Double
    let partials: [Partial]
    let attack: Double // linear attack, seconds
    let sustain: Double // full-level hold after the attack, seconds
    let decayRate: Double // exponential decay rate after the sustain, 1/s
}

let specs = [
    // Soft bell swell: gentle rise, brief hold, long ring-out. Single-timer
    // finish and focus-phase end.
    SoundSpec(
        filename: "alarm-major.caf", duration: 5.0,
        partials: [
            Partial(frequency: 660, amplitude: 0.50),
            Partial(frequency: 990, amplitude: 0.25),
            Partial(frequency: 1320, amplitude: 0.12),
        ],
        attack: 0.8, sustain: 0.4, decayRate: 1.6
    ),
    // Single soft tone: break end — noticeable, not startling.
    SoundSpec(
        filename: "chime-minor.caf", duration: 1.5,
        partials: [
            Partial(frequency: 880, amplitude: 0.40),
            Partial(frequency: 1320, amplitude: 0.15),
        ],
        attack: 0.02, sustain: 0.05, decayRate: 3.5
    ),
]

func envelope(at t: Double, spec: SoundSpec) -> Double {
    let level: Double
    if t < spec.attack {
        level = t / spec.attack
    } else if t < spec.attack + spec.sustain {
        level = 1
    } else {
        level = exp(-spec.decayRate * (t - spec.attack - spec.sustain))
    }
    // 50 ms release against end-of-file clicks.
    return level * min(1, max(0, (spec.duration - t) / 0.05))
}

func render(spec: SoundSpec, into directory: URL) throws {
    let sampleRate = 44100.0
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
    ) else {
        throw NSError(domain: "generate_sounds", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "could not create render format",
        ])
    }

    let engine = AVAudioEngine()
    var frameIndex = 0
    let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let samples = UnsafeMutableBufferPointer<Float>(buffers[0])
        for frame in 0..<Int(frameCount) {
            let t = Double(frameIndex + frame) / sampleRate
            var value = 0.0
            for partial in spec.partials {
                value += partial.amplitude * sin(2 * .pi * partial.frequency * t)
            }
            samples[frame] = Float(value * envelope(at: t, spec: spec))
        }
        frameIndex += Int(frameCount)
        return noErr
    }
    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try engine.start()

    let url = directory.appendingPathComponent(spec.filename)
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(
        forWriting: url, settings: format.settings,
        commonFormat: .pcmFormatFloat32, interleaved: false
    )
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: engine.manualRenderingFormat,
        frameCapacity: engine.manualRenderingMaximumFrameCount
    ) else {
        throw NSError(domain: "generate_sounds", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "could not allocate render buffer",
        ])
    }

    let totalFrames = AVAudioFramePosition(spec.duration * sampleRate)
    while engine.manualRenderingSampleTime < totalFrames {
        let remaining = AVAudioFrameCount(totalFrames - engine.manualRenderingSampleTime)
        let status = try engine.renderOffline(min(remaining, buffer.frameCapacity), to: buffer)
        guard status == .success else {
            throw NSError(domain: "generate_sounds", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "offline render failed: \(status)",
            ])
        }
        try file.write(from: buffer)
    }
    engine.stop()
    print("wrote \(url.path) (\(spec.duration) s)")
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Sounds"
let outDir = URL(fileURLWithPath: outPath)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for spec in specs {
    try render(spec: spec, into: outDir)
}
