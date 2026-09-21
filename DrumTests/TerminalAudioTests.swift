import AppKit
import AVFAudio
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalAudioTests {
    @Test func disabledAudioDoesNotPrepareOrPlayAnything() {
        let playback = RecordingPlayback()
        let audio = TerminalAudio(playback: playback, previewPlayback: RecordingPlayback())
        audio.setActive(true)
        audio.setPoweredOn(true)
        audio.ringBell()
        audio.clickKey()
        #expect(playback.prepared.isEmpty)
        #expect(playback.events.isEmpty)
    }

    @Test func powerAndActivityControlAudioWithoutReplayingBoot() {
        let playback = RecordingPlayback()
        let audio = TerminalAudio(playback: playback, previewPlayback: RecordingPlayback())
        var settings = SoundSettings()
        settings.boot.enabled = true
        settings.bell.enabled = true
        settings.keyClick.enabled = true
        settings.hum.enabled = true
        audio.configure(settings)
        audio.setPoweredOn(true)
        #expect(playback.events.isEmpty)
        audio.setActive(true)
        #expect(playback.events.filter { $0.sound == .boot }.count == 1)
        #expect(playback.events.contains { $0.sound == .hum && $0.looping })
        let preparations = playback.prepared.count
        audio.ringBell()
        audio.clickKey()
        #expect(playback.prepared.count == preparations) // No synthesis/setup during input.
        #expect(playback.events.suffix(2).map(\.sound) == [.bell, .keyClick])
        audio.setActive(false)
        let count = playback.events.count
        audio.ringBell()
        audio.clickKey()
        #expect(playback.events.count == count)
        #expect(playback.live.isEmpty)
        audio.setActive(true)
        #expect(playback.events.filter { $0.sound == .boot }.count == 1)
        audio.setPoweredOn(false)
        #expect(playback.live.isEmpty)
        audio.setPoweredOn(true)
        #expect(playback.events.filter { $0.sound == .boot }.count == 2)
        settings.bell.enabled = false
        settings.hum.volume = 0
        audio.configure(settings)
        #expect(!playback.live.contains(.hum))
        let bells = playback.events.filter { $0.sound == .bell }.count
        audio.ringBell()
        #expect(playback.events.filter { $0.sound == .bell }.count == bells)
    }

    @Test func previewIsFiniteAndDoesNotEnableSounds() async throws {
        let playback = RecordingPlayback()
        let preview = RecordingPlayback()
        let audio = TerminalAudio(playback: playback, previewPlayback: preview)
        audio.setActive(true)
        audio.setPoweredOn(true)
        audio.preview(.hum)
        #expect(preview.events.count == 1)
        #expect(preview.events.first?.looping == false)
        #expect(playback.events.isEmpty)
        audio.setActive(false)
        #expect(preview.live.isEmpty)
        audio.setActive(true)
        audio.preview(.bell)
        try await Task.sleep(for: .milliseconds(450))
        #expect(preview.live.isEmpty)
        audio.ringBell()
        #expect(playback.events.isEmpty)
    }

    @Test func audioFailureLeavesTerminalUsable() {
        let playback = RecordingPlayback()
        playback.failPreparation = true
        let audio = TerminalAudio(playback: playback, previewPlayback: RecordingPlayback())
        var settings = SoundSettings()
        settings.bell.enabled = true
        audio.configure(settings)
        audio.setActive(true)
        audio.setPoweredOn(true)
        #expect(audio.errorMessage != nil)
        audio.configure(SoundSettings())
        #expect(audio.errorMessage == nil)
    }

    @Test func preferencesPersistIndependentlyOfCRTSettings() throws {
        let domain = "drum.audio.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let first = AppState(defaults: defaults)
        #expect(TerminalSound.allCases.allSatisfy { !first.sound[$0].enabled })
        first.sound.bell.enabled = true
        first.sound.keyClick.enabled = true
        first.sound.keyClick.volume = 0.47
        first.sound.mains = .hz50
        first.crt.enabled = false
        let second = AppState(defaults: defaults)
        #expect(second.sound == first.sound)
        #expect(second.terminal.view.keyClicksEnabled)
        #expect(!second.crt.enabled)
        let decoded = try JSONDecoder().decode(SoundSettings.self, from: Data(#"{"hum":{"enabled":true,"volume":5}}"#.utf8))
        #expect(decoded.hum.volume == 1)
        #expect(!decoded.bell.enabled)
    }

    @Test func onlyParsedBELRingsAndOnlyTerminalKeysClick() throws {
        let view = DrumTerminalView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        let events = RecordingSoundEvents()
        view.soundEvents = events
        view.feed(text: "hello\u{07}")
        #expect(events.bells == 1)
        view.feed(text: "\u{1B}]0;window title\u{07}") // OSC terminator is not BEL.
        #expect(events.bells == 1)
        view.feed(text: "output")
        view.insertText("pasted text", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(events.clicks == 0)

        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view // No session, so no shell is launched.
        defer { window.contentView = nil; window.close() }
        window.makeFirstResponder(view)
        view.keyClicksEnabled = true
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                               timestamp: 0, windowNumber: window.windowNumber,
                                               context: nil, characters: "a", charactersIgnoringModifiers: "a",
                                               isARepeat: false, keyCode: 0))
        view.noteKeyDown(key)
        #expect(events.clicks == 1)
        let command = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
                                                   timestamp: 0, windowNumber: window.windowNumber,
                                                   context: nil, characters: "v", charactersIgnoringModifiers: "v",
                                                   isARepeat: false, keyCode: 9))
        view.noteKeyDown(command)
        #expect(events.clicks == 1)
        window.makeFirstResponder(nil)
        view.noteKeyDown(key)
        #expect(events.clicks == 1)
        window.makeFirstResponder(view)
        view.keyClicksEnabled = false
        view.noteKeyDown(key)
        #expect(events.clicks == 1)
    }
}

@MainActor
private final class RecordingPlayback: SoundPlayback {
    struct Event { let sound: TerminalSound; let looping: Bool }
    var prepared: [TerminalSound] = []
    var events: [Event] = []
    var live: Set<TerminalSound> = []
    var failPreparation = false
    func prepare(_ sound: TerminalSound, settings: SoundSettings) throws {
        if failPreparation { throw CocoaError(.fileReadUnknown) }
        prepared.append(sound)
    }
    func play(_ sound: TerminalSound, volume: Float, looping: Bool) {
        events.append(Event(sound: sound, looping: looping))
        live.insert(sound)
    }
    func setVolume(_ volume: Float, for sound: TerminalSound) {}
    func stop(_ sound: TerminalSound) { live.remove(sound) }
    func stopAll() { live.removeAll() }
}

@MainActor
private final class RecordingSoundEvents: TerminalSoundEvents {
    var bells = 0
    var clicks = 0
    func ringBell() { bells += 1 }
    func clickKey() { clicks += 1 }
}

struct SoundWaveformTests {
    @Test func durationsLevelsAndDecoding() throws {
        let durations: [TerminalSound: Double] = [.boot: 0.125, .bell: 0.25, .keyClick: 0.003, .hum: 1, .flyback: 1]
        for sound in TerminalSound.allCases {
            let samples = SoundWaveform.samples(for: sound, settings: SoundSettings())
            #expect(samples.allSatisfy { $0.isFinite && abs($0) < 0.5 })
            #expect(samples.contains { $0 != 0 })
            #expect(samples.first == 0)
            if !sound.isAmbient { #expect(samples.last == 0) }
            let player = try AVAudioPlayer(data: SoundWaveform.wav(for: sound, settings: SoundSettings()))
            #expect(abs(player.duration - durations[sound]!) < 1 / Double(SoundWaveform.sampleRate))
            #expect(player.numberOfChannels == 1)
        }
    }

    @Test func frequenciesMatchSelectedTuning() {
        var settings = SoundSettings()
        for pitch in SoundSettings.FlybackPitch.allCases {
            settings.flybackPitch = pitch
            let samples = SoundWaveform.samples(for: .flyback, settings: settings)
            #expect(amplitude(samples, at: Double(pitch.rawValue)) > 0.02)
            #expect(amplitude(samples, at: 1000) < 0.0001)
        }
        for mains in SoundSettings.Mains.allCases {
            settings.mains = mains
            let samples = SoundWaveform.samples(for: .hum, settings: settings)
            #expect(amplitude(samples, at: Double(mains.rawValue)) > 0.09)
            #expect(amplitude(samples, at: Double(mains.rawValue * 2)) > 0.03)
            #expect(amplitude(samples, at: Double(mains.rawValue * 3)) > 0.01)
        }
        for sound in [TerminalSound.boot, .bell] {
            let samples = SoundWaveform.samples(for: sound, settings: settings)
            #expect(amplitude(samples, at: 785) > 0.2)
            #expect(amplitude(samples, at: 1000) < 0.005)
        }
    }

    private func amplitude(_ samples: [Float], at frequency: Double) -> Double {
        var real = 0.0, imaginary = 0.0
        for (index, sample) in samples.enumerated() {
            let phase = 2 * Double.pi * frequency * Double(index) / Double(SoundWaveform.sampleRate)
            real += Double(sample) * cos(phase)
            imaginary += Double(sample) * sin(phase)
        }
        return 2 * hypot(real, imaginary) / Double(samples.count)
    }
}
