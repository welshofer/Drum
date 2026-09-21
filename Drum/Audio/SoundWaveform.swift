import Foundation

/// Finite, deterministic PCM, generated only when a sound is prepared.
/// These are restrained approximations, not recordings or circuit emulation.
enum SoundWaveform {
    static let sampleRate = 48_000

    static func samples(for sound: TerminalSound, settings: SoundSettings) -> [Float] {
        let duration: Double = switch sound {
        case .boot: 0.125
        case .bell: 0.250
        case .keyClick: 0.003
        case .flyback, .hum: 1
        }
        let count = Int(duration * Double(sampleRate))
        return (0..<count).map { index in
            let t = Double(index) / Double(sampleRate)
            let value: Double
            switch sound {
            case .boot, .bell:
                // Rounded pulse: limited odd harmonics avoid a harsh aliased square wave.
                let phase = 2 * Double.pi * 785 * t
                let pulse = sin(phase) + sin(3 * phase) / 3 + sin(5 * phase) / 5 + sin(7 * phase) / 7
                let ramp = min(1, min(t / 0.002, Double(count - 1 - index) / 96))
                value = 0.24 * pulse * ramp
            case .keyClick:
                // A short bipolar, heavily damped impulse, with no sustained pitch.
                let x = t / 0.00025
                let tail = Double(count - 1 - index) / Double(count - 1)
                value = 0.45 * x * (2 - x) * exp(-x) * tail
            case .flyback:
                value = 0.025 * sin(2 * Double.pi * Double(settings.flybackPitch.rawValue) * t)
            case .hum:
                let phase = 2 * Double.pi * Double(settings.mains.rawValue) * t
                value = 0.1 * (sin(phase) + 0.35 * sin(2 * phase) + 0.15 * sin(3 * phase))
            }
            return Float(value)
        }
    }

    /// One-second ambient buffers contain whole cycles, so repeated playback is seamless.
    static func wav(for sound: TerminalSound, settings: SoundSettings) -> Data {
        let samples = samples(for: sound, settings: settings)
        let byteCount = UInt32(samples.count * 2)
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(36) + byteCount)
        data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16))
        word(UInt16(1)); word(UInt16(1)); word(UInt32(sampleRate))
        word(UInt32(sampleRate * 2)); word(UInt16(2)); word(UInt16(16))
        data.append(contentsOf: "data".utf8); word(byteCount)
        for sample in samples { word(Int16((sample * Float(Int16.max)).rounded())) }
        return data
    }
}
