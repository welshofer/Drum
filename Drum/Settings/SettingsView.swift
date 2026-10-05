import SwiftUI

/// Live settings, no Apply button. Everything writes straight into `AppState`.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Appearance", systemImage: "display") { AppearanceSettingsView() }
            Tab("Sound", systemImage: "speaker.wave.2") { SoundSettingsView() }
            Tab("Terminal", systemImage: "terminal") { TerminalSettingsView() }
        }
        .frame(width: 500, height: 660)
    }
}

private struct AppearanceSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Phosphor") {
                Picker("Preset", selection: Binding(
                    get: { state.preset },
                    set: { state.select($0) })) {
                    ForEach(PhosphorPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                ColorPicker("Custom colour", selection: $state.customColor, supportsOpacity: false)
                LabeledSlider("Bloom radius", value: $state.crt.phosphor.bloomRadius, in: 0...8, format: "%.1f pt")
                    .disabled(!state.crt.enabled)
                LabeledSlider("Bloom strength", value: $state.crt.phosphor.bloomStrength, in: 0...2, format: "%.2f")
                    .disabled(!state.crt.enabled)
            }

            Section("Tube") {
                Toggle("CRT effect", isOn: $state.crt.enabled)
                Toggle("Sync wobble", isOn: $state.crt.animated)
                    .disabled(!state.crt.enabled)
                    .help("Adds subtle motion to the CRT picture. Cursor blinking, terminal updates, and power transitions are separate. Reduce Motion pauses wobble.")
                CRTSlidersView(crt: $state.crt)
                    .disabled(!state.crt.enabled)
            } footer: {
                if !state.crt.enabled {
                    Text("Bloom and tube effects resume when CRT is on. Font and phosphor colour remain active.")
                }
            }

            Section("Font") {
                Picker("Face", selection: Binding(
                    get: { state.font },
                    set: { state.select($0) })) {
                    ForEach(TerminalFontChoice.allCases) { font in
                        Text(font.title).tag(font)
                    }
                }
                LabeledSlider("Size", value: $state.fontSize, in: 8...48, format: "%.0f pt")
            }
        }
        .formStyle(.grouped)
    }
}

/// The per-uniform sliders, extracted to keep `SettingsView` short.
struct CRTSlidersView: View {
    @Binding var crt: CRTSettings

    var body: some View {
        LabeledSlider("Brightness", value: $crt.brightness, in: 0.5...2, format: "%.2f×")
        LabeledSlider("Curvature X", value: $crt.barrelX, in: 0...0.15, format: "%.3f")
        LabeledSlider("Curvature Y", value: $crt.barrelY, in: 0...0.15, format: "%.3f")
        LabeledSlider("Sync wobble", value: $crt.wobble, in: 0...0.01, format: "%.4f")
        LabeledSlider("Scanlines", value: $crt.scanlines, in: 0...0.5, format: "%.2f")
        LabeledSlider("Aperture grille", value: $crt.grille, in: 0...0.3, format: "%.2f")
        LabeledSlider("Vignette", value: $crt.vignette, in: 0...1.5, format: "%.2f")
        LabeledSlider("Bezel radius", value: $crt.bezelCornerRadius, in: 0...120, format: "%.0f pt")
        Button("Reset tube to defaults") {
            let phosphor = crt.phosphor
            crt = CRTSettings()
            crt.phosphor = phosphor
        }
    }
}

/// Slider with a trailing numeric readout. Generic over the float type so the
/// `Float` uniforms and the `CGFloat`/`Double` sizes share one control.
struct LabeledSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: V
    let range: ClosedRange<V>
    let format: String

    init(_ title: String, value: Binding<V>, in range: ClosedRange<V>, format: String) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        HStack {
            Slider(value: $value, in: range, label: { Text(title) })
            Text(String(format: format, Double(value)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }
}
