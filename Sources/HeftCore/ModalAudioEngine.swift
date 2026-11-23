import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import os

/// Pure value-type modal resonator voice for real-time zero-allocation audio synthesis.
public struct ModalVoice: Sendable {
    public var active: Bool = false
    public var sampleIndex: Int = 0
    public var totalSamples: Int = 0
    public var freqs: (Double, Double, Double, Double) = (0, 0, 0, 0)
    public var decays: (Double, Double, Double, Double) = (1, 1, 1, 1)
    public var amps: (Double, Double, Double, Double) = (0, 0, 0, 0)
    public var pitchGlide: Double = 0.0
    public var crackSampleOffset: Int = -1
    public var crackAmplitude: Double = 0.0

    public init() {}
}

/// Lock-free / real-time-safe modal impact synthesizer operating inside the <12 ms Haas fusion window.
/// Maps `StressVector` `(mass, tension, fracture)` onto physical eigenmodes so the human auditory
/// cortex binds the harmonic tail directly into the mechanical click of the MacBook keycap.
public struct ModalSynthesizer: Sendable {
    public static let maxVoices = 12
    public var sampleRate: Double
    public var masterGainLinear: Float
    private var voices: [ModalVoice]
    private var nextVoiceCursor: Int = 0

    public init(sampleRate: Double = 48_000.0, gainDB: Double = -32.0) {
        self.sampleRate = sampleRate
        self.masterGainLinear = Float(pow(10.0, gainDB / 20.0))
        self.voices = Array(repeating: ModalVoice(), count: Self.maxVoices)
    }

    public mutating func setGainDB(_ db: Double) {
        let clamped = min(-6.0, max(-60.0, db))
        self.masterGainLinear = Float(pow(10.0, clamped / 20.0))
    }

    /// Triggers a sub-10ms physical material transient shaped by the live structural stress vector.
    public mutating func triggerKeyImpact(stress: StressVector, keyPitchJitter: Double = 0.0) {
        var voice = ModalVoice()
        voice.active = true
        voice.sampleIndex = 0

        let jitter = 1.0 + max(-0.035, min(0.035, keyPitchJitter))

        if stress.fracture >= 0.25 {
            // Cracked Ceramic: detuned split eigenmodes (beating) + delayed micro-crack impulse at 2.6 ms.
            let severity = StressVector.clamp(stress.fracture)
            voice.totalSamples = Int(sampleRate * 0.0095) // 9.5 ms (< 12 ms Haas limit)
            voice.freqs = (
                1580.0 * jitter,
                1668.0 * jitter, // Inharmonic split pair creates brittle rattle
                2940.0 * jitter,
                3145.0 * jitter
            )
            voice.decays = (420.0, 460.0, 580.0, 640.0)
            voice.amps = (0.45, 0.42, 0.30, 0.28)
            voice.pitchGlide = -18.0 * severity
            voice.crackSampleOffset = Int(sampleRate * 0.0026)
            voice.crackAmplitude = 0.55 * severity
        } else if stress.mass >= 0.50 {
            // Dense Cast Lead: downward-shifted low modal fundamentals + viscous high-frequency damping.
            let heaviness = StressVector.clamp(stress.mass)
            let scale = 1.0 - 0.52 * heaviness
            voice.totalSamples = Int(sampleRate * 0.0090) // 9.0 ms
            voice.freqs = (
                540.0 * scale * jitter,
                820.0 * scale * jitter,
                1240.0 * scale * jitter,
                1720.0 * scale * jitter
            )
            voice.decays = (290.0, 380.0, 620.0, 900.0)
            voice.amps = (0.68, 0.42, 0.16, 0.06)
            voice.pitchGlide = -42.0 * heaviness
        } else if stress.tension >= 0.50 {
            // Tensioned Spring Steel: taut upper partials with slight upward tension bend.
            let pull = StressVector.clamp(stress.tension)
            let stretch = 1.0 + 0.22 * pull
            voice.totalSamples = Int(sampleRate * 0.0068) // 6.8 ms
            voice.freqs = (
                2120.0 * stretch * jitter,
                3980.0 * stretch * jitter,
                5640.0 * stretch * jitter,
                7420.0 * stretch * jitter
            )
            voice.decays = (520.0, 610.0, 720.0, 880.0)
            voice.amps = (0.38, 0.34, 0.24, 0.14)
            voice.pitchGlide = 14.0 * pull
        } else {
            // Machined 6061 Aluminum / Titanium: ultra-short, crystalline, weightless precision click tail.
            voice.totalSamples = Int(sampleRate * 0.0052) // 5.2 ms
            voice.freqs = (
                2860.0 * jitter,
                4480.0 * jitter,
                6720.0 * jitter,
                8940.0 * jitter
            )
            voice.decays = (760.0, 890.0, 1080.0, 1320.0)
            voice.amps = (0.36, 0.28, 0.18, 0.10)
            voice.pitchGlide = 0.0
        }

        voices[nextVoiceCursor] = voice
        nextVoiceCursor = (nextVoiceCursor + 1) % Self.maxVoices
    }

    /// Triggers a crisp 11 ms phase-coherent harmonic lock when a fractured workspace snaps back to green.
    public mutating func triggerCrystallizationLock() {
        var voice = ModalVoice()
        voice.active = true
        voice.sampleIndex = 0
        voice.totalSamples = Int(sampleRate * 0.011) // 11 ms Haas upper bound
        voice.freqs = (2637.02, 3951.07, 5274.04, 7902.13) // E7 - B7 - E8 - B8 fifth/octave lock
        voice.decays = (340.0, 410.0, 490.0, 620.0)
        voice.amps = (0.40, 0.32, 0.22, 0.12)
        voices[nextVoiceCursor] = voice
        nextVoiceCursor = (nextVoiceCursor + 1) % Self.maxVoices
    }

    /// Renders mono float PCM frames with zero memory allocations.
    public mutating func renderFrame() -> Float {
        var accum: Double = 0.0
        let invSR = 1.0 / sampleRate
        let twoPi = 2.0 * Double.pi

        for idx in 0..<Self.maxVoices {
            guard voices[idx].active else { continue }
            let n = voices[idx].sampleIndex
            if n >= voices[idx].totalSamples {
                voices[idx].active = false
                continue
            }

            let t = Double(n) * invSR
            let glideFactor = 1.0 + voices[idx].pitchGlide * t

            let m0 = voices[idx].amps.0 * exp(-voices[idx].decays.0 * t) * sin(twoPi * voices[idx].freqs.0 * glideFactor * t)
            let m1 = voices[idx].amps.1 * exp(-voices[idx].decays.1 * t) * sin(twoPi * voices[idx].freqs.1 * glideFactor * t)
            let m2 = voices[idx].amps.2 * exp(-voices[idx].decays.2 * t) * sin(twoPi * voices[idx].freqs.2 * glideFactor * t)
            let m3 = voices[idx].amps.3 * exp(-voices[idx].decays.3 * t) * sin(twoPi * voices[idx].freqs.3 * glideFactor * t)

            var sample = m0 + m1 + m2 + m3

            // Secondary micro-crack scatter impulse for fractured ceramic state.
            let crackOffset = voices[idx].crackSampleOffset
            if crackOffset > 0 && n >= crackOffset && n < crackOffset + 28 {
                let ct = Double(n - crackOffset) * invSR
                sample += voices[idx].crackAmplitude * exp(-1800.0 * ct) * sin(twoPi * 3620.0 * ct)
            }

            // Smooth raised-cosine fade-out on final 32 samples to prevent DAC truncation clicks.
            let remaining = voices[idx].totalSamples - n
            if remaining < 32 {
                sample *= Double(remaining) / 32.0
            }

            accum += sample
            voices[idx].sampleIndex = n + 1
        }

        let scaled = Float(accum) * masterGainLinear
        return max(-0.95, min(0.95, scaled))
    }

    /// Renders an offline buffer for deterministic acoustic physics testing and spectral verification.
    public mutating func renderBuffer(frameCount: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            out[i] = renderFrame()
        }
        return out
    }
}

/// Real-time CoreAudio engine wrapping `ModalSynthesizer` on a low-latency 64-frame HAL output unit.
public final class ModalAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var synth: ModalSynthesizer
    private var unfairLock = os_unfair_lock_s()
    public private(set) var isRunning = false
    public private(set) var hardwareSampleRate: Double = 48_000.0
    public private(set) var hardwareBufferFrames: UInt32 = 64

    public init(gainDB: Double = -32.0) {
        self.synth = ModalSynthesizer(sampleRate: 48_000.0, gainDB: gainDB)
    }

    /// Starts the low-latency CoreAudio render graph and requests a 64-frame hardware I/O buffer (~1.33 ms).
    @discardableResult
    public func start() -> Bool {
        if isRunning { return true }

        let outputNode = engine.outputNode
        let hwFormat = outputNode.inputFormat(forBus: 0)
        let sr = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 48_000.0
        self.hardwareSampleRate = sr

        os_unfair_lock_lock(&unfairLock)
        synth.sampleRate = sr
        os_unfair_lock_unlock(&unfairLock)

        // Request minimal CoreAudio HAL buffer frame size (64 frames = 1.33 ms @ 48 kHz)
        // so acoustic transient lands well inside the 12 ms Haas precedence window.
        if let audioUnit = outputNode.audioUnit {
            var desiredFrames: UInt32 = 64
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioDevicePropertyBufferFrameSize,
                kAudioUnitScope_Global,
                0,
                &desiredFrames,
                UInt32(MemoryLayout<UInt32>.size)
            )
            var actualFrames: UInt32 = 0
            var propSize = UInt32(MemoryLayout<UInt32>.size)
            let readStatus = AudioUnitGetProperty(
                audioUnit,
                kAudioDevicePropertyBufferFrameSize,
                kAudioUnitScope_Global,
                0,
                &actualFrames,
                &propSize
            )
            if readStatus == noErr && actualFrames > 0 {
                self.hardwareBufferFrames = actualFrames
            } else if status == noErr {
                self.hardwareBufferFrames = desiredFrames
            }
        }

        guard let renderFormat = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else {
            return false
        }

        let node = AVAudioSourceNode(format: renderFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            os_unfair_lock_lock(&self.unfairLock)
            for frame in 0..<frames {
                let sample = self.synth.renderFrame()
                for buffer in ablPointer {
                    if let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        ptr[frame] = sample
                    }
                }
            }
            os_unfair_lock_unlock(&self.unfairLock)
            return noErr
        }

        self.sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: renderFormat)

        do {
            try engine.start()
            self.isRunning = true
            return true
        } catch {
            self.isRunning = false
            return false
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        isRunning = false
    }

    public func setGainDB(_ db: Double) {
        os_unfair_lock_lock(&unfairLock)
        synth.setGainDB(db)
        os_unfair_lock_unlock(&unfairLock)
    }

    public func triggerKeystroke(stress: StressVector, keyCode: UInt16 = 0) {
        // Deterministic per-keycap subtle modal variance (±2.8%) just like real chassis geometry.
        let normalizedKey = Double((Int(keyCode) * 73) % 19 - 9) / 320.0
        os_unfair_lock_lock(&unfairLock)
        synth.triggerKeyImpact(stress: stress, keyPitchJitter: normalizedKey)
        os_unfair_lock_unlock(&unfairLock)
    }

    public func triggerCrystallization() {
        os_unfair_lock_lock(&unfairLock)
        synth.triggerCrystallizationLock()
        os_unfair_lock_unlock(&unfairLock)
    }

    public var bufferLatencyMilliseconds: Double {
        (Double(hardwareBufferFrames) / max(1.0, hardwareSampleRate)) * 1_000.0
    }
}
