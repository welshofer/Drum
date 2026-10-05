import Foundation
import Observation

@MainActor
protocol TerminalSoundEvents: AnyObject {
    func ringBell()
    func clickKey()
}

/// Event policy and lifetime, independent of AVFoundation for deterministic tests.
@MainActor @Observable
final class TerminalAudio: TerminalSoundEvents {
    private(set) var errorMessage: String?
    private(set) var previewingSound: TerminalSound?
    @ObservationIgnored private let playback: any SoundPlayback
    @ObservationIgnored private let previewPlayback: any SoundPlayback
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var settings = SoundSettings()
    @ObservationIgnored private var poweredOn = false
    @ObservationIgnored private var active = false
    @ObservationIgnored private var pendingBoot = false

    init(playback: any SoundPlayback = NativeSoundPlayback(),
         previewPlayback: any SoundPlayback = NativeSoundPlayback()) {
        self.playback = playback
        self.previewPlayback = previewPlayback
    }

    func configure(_ settings: SoundSettings) {
        self.settings = settings
        errorMessage = nil
        stopPreview()
        reconcile()
    }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        if !active { stopPreview() }
        reconcile()
    }

    func setPoweredOn(_ poweredOn: Bool) {
        guard self.poweredOn != poweredOn else { return }
        self.poweredOn = poweredOn
        pendingBoot = poweredOn && settings.boot.enabled
        if !poweredOn { stopPreview() }
        reconcile()
    }

    func ringBell() { playEvent(.bell) }
    func clickKey() { playEvent(.keyClick) }

    private func playEvent(_ sound: TerminalSound) {
        guard poweredOn, active, settings[sound].enabled, settings.gain(for: sound) > 0 else { return }
        do {
            try playback.play(sound, volume: settings.gain(for: sound), looping: false)
        } catch {
            errorMessage = "Audio playback is unavailable. Try turning the sound off and on again."
        }
    }

    private func reconcile() {
        guard poweredOn, active else { playback.stopAll(); return }
        for sound in TerminalSound.allCases {
            let gain = settings.gain(for: sound)
            guard settings[sound].enabled, gain > 0 else { playback.stop(sound); continue }
            do {
                try playback.prepare(sound, settings: settings)
                playback.setVolume(gain, for: sound)
                if sound.isAmbient { try playback.play(sound, volume: gain, looping: true) }
            } catch {
                errorMessage = "Could not prepare \(sound.title.lowercased()). Try turning it off and on again."
            }
        }
        if pendingBoot {
            pendingBoot = false
            playEvent(.boot)
        }
    }

    /// Previews do not enable a preference or leave an ambient loop running.
    func preview(_ sound: TerminalSound) {
        guard active else { return }
        stopPreview()
        do {
            try previewPlayback.prepare(sound, settings: settings)
            try previewPlayback.play(sound, volume: settings.gain(for: sound), looping: false)
            errorMessage = nil
            previewingSound = sound
            previewTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(sound.isAmbient ? 1100 : 350))
                guard !Task.isCancelled else { return }
                self?.stopPreview()
            }
        } catch {
            stopPreview()
            errorMessage = "Could not play the sound preview. Try again."
        }
    }

    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewingSound = nil
        previewPlayback.stopAll()
    }
}
