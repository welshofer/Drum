import SwiftUI

struct SoundSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                SoundSettingsRow(sound: .boot, option: $state.sound.boot)
                SoundSettingsRow(sound: .bell, option: $state.sound.bell)
                SoundSettingsRow(sound: .keyClick, option: $state.sound.keyClick)
            } header: {
                Text("Keyboard & power")
            } footer: {
                Text("The boot tone plays at launch and on Power Cycle. The bell sounds when a program sends BEL; Ctrl-G depends on the running program.")
            }
            Section {
                SoundSettingsRow(sound: .flyback, option: $state.sound.flyback)
                Picker("Flyback frequency", selection: $state.sound.flybackPitch) {
                    ForEach(SoundSettings.FlybackPitch.allCases, id: \.self) { pitch in
                        Text("\(pitch.rawValue.formatted()) Hz").tag(pitch)
                    }
                }
                SoundSettingsRow(sound: .hum, option: $state.sound.hum)
                Picker("Hum frequency", selection: $state.sound.mains) {
                    ForEach(SoundSettings.Mains.allCases, id: \.self) { mains in
                        Text("\(mains.rawValue) Hz").tag(mains)
                    }
                }
            } header: {
                Text("Room tone")
            } footer: {
                Text("VT100-inspired synthesis. All sounds start off and pause when Drum is inactive. Ambient previews last one second.")
            }
            if let error = state.audio.errorMessage {
                Text(error).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { state.audio.stopPreview() }
    }
}

private struct SoundSettingsRow: View {
    let sound: TerminalSound
    @Binding var option: SoundOption
    @Environment(AppState.self) private var state

    private var isPreviewing: Bool { state.audio.previewingSound == sound }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(sound.title, isOn: $option.enabled)
                Spacer()
                if isPreviewing {
                    Text("Playing")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Button(isPreviewing ? "Stop" : "Preview",
                       systemImage: isPreviewing ? "stop.fill" : "speaker.wave.2") {
                    if isPreviewing { state.audio.stopPreview() } else { state.audio.preview(sound) }
                }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("\(isPreviewing ? "Stop preview of" : "Preview") \(sound.title.lowercased())")
                    .accessibilityValue(isPreviewing ? "Playing" : "Stopped")
                    .help("\(isPreviewing ? "Stop preview of" : "Preview") \(sound.title.lowercased())")
            }
            HStack {
                Slider(value: $option.volume, in: 0...1) { Text("Volume") }
                    .accessibilityLabel("\(sound.title) volume")
                Text(option.volume.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}
