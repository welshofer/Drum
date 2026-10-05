import AVFAudio

@MainActor
protocol SoundPlayback: AnyObject {
    func prepare(_ sound: TerminalSound, settings: SoundSettings) throws
    func play(_ sound: TerminalSound, volume: Float, looping: Bool) throws
    /// Nil when no voice is playing; otherwise its estimated time to completion.
    func remainingPlaybackTime(for sound: TerminalSound) -> TimeInterval?
    func setVolume(_ volume: Float, for sound: TerminalSound)
    func stop(_ sound: TerminalSound)
    func stopAll()
}

/// AVFoundation owns decoding, mixing and playback. No audio callback, render
/// timer or synthesis runs on the terminal's input/drawing paths.
@MainActor
final class NativeSoundPlayback: SoundPlayback {
    private enum PlaybackError: Error { case unavailable }
    private var players: [TerminalSound: [AVAudioPlayer]] = [:]
    private var pitches: [TerminalSound: Int] = [:]
    private var retiring: [TerminalSound: Task<Void, Never>] = [:]

    func prepare(_ sound: TerminalSound, settings: SoundSettings) throws {
        let pitch = sound == .hum ? settings.mains.rawValue : settings.flybackPitch.rawValue
        if players[sound] != nil, !sound.isAmbient || pitches[sound] == pitch { return }
        stop(sound)
        let data = SoundWaveform.wav(for: sound, settings: settings)
        let voices = try (0..<(sound == .keyClick ? 4 : 1)).map { _ in
            let player = try AVAudioPlayer(data: data)
            guard player.prepareToPlay() else { throw PlaybackError.unavailable }
            return player
        }
        players[sound] = voices
        pitches[sound] = pitch
    }

    func play(_ sound: TerminalSound, volume: Float, looping: Bool) throws {
        retiring.removeValue(forKey: sound)?.cancel()
        guard let voices = players[sound], let player = voices.first(where: { !$0.isPlaying }) ?? voices.first else { return }
        if sound.isAmbient, player.isPlaying {
            player.setVolume(volume, fadeDuration: 0.08)
            return
        }
        // Repeated BEL never creates an unbounded queue of alerts.
        if !sound.isAmbient, player.isPlaying { return }
        player.currentTime = 0
        player.numberOfLoops = looping ? -1 : 0
        player.volume = sound.isAmbient ? 0 : volume
        guard player.play() else { throw PlaybackError.unavailable }
        if sound.isAmbient { player.setVolume(volume, fadeDuration: 0.08) }
    }

    func setVolume(_ volume: Float, for sound: TerminalSound) {
        for player in players[sound] ?? [] { player.setVolume(volume, fadeDuration: 0.08) }
    }

    func remainingPlaybackTime(for sound: TerminalSound) -> TimeInterval? {
        players[sound]?.filter(\.isPlaying).map { max(0, $0.duration - $0.currentTime) }.max()
    }

    func stop(_ sound: TerminalSound) {
        retiring.removeValue(forKey: sound)?.cancel()
        guard let voices = players.removeValue(forKey: sound) else { return }
        pitches.removeValue(forKey: sound)
        if sound.isAmbient {
            for player in voices { player.setVolume(0, fadeDuration: 0.08) }
            retiring[sound] = Task {
                try? await Task.sleep(for: .milliseconds(100))
                for player in voices { player.stop() }
            }
        } else {
            for player in voices { player.stop() }
        }
    }

    func stopAll() { for sound in TerminalSound.allCases { stop(sound) } }
}
