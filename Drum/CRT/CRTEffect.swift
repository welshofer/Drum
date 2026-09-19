import SwiftUI

/// The modifier chain. Order is load-bearing: bloom → mask → barrel → bezel.
/// Bloom runs before the barrel so the glow curves with the glass.
/// Applied once, on the terminal container. Never on the window.
struct CRTEffect: ViewModifier {
    let settings: CRTSettings
    let time: TimeInterval
    let liveResize: Bool

    private var bloom: Shader {
        let function = liveResize ? DrumBundle.shaders.crtBloomFast : DrumBundle.shaders.crtBloom
        return function(.float(settings.phosphor.bloomRadius),
                        .float(settings.phosphor.bloomStrength),
                        .color(settings.phosphor.swiftUIColor))
    }

    /// The wobble's sine runs at 1.7 rad/s. `time` is wrapped at a whole
    /// number of its periods before the narrowing to `Float`: the raw
    /// reference-date offset (~8e8 s) has a `Float` ULP of 64 s, which would
    /// freeze the wobble entirely. Wrapped, precision is ~3e-5 s.
    static let timePeriod: TimeInterval = 100 * 2 * .pi / 1.7

    func body(content: Content) -> some View {
        content
            .layerEffect(
                bloom,
                maxSampleOffset: CGSize(width: settings.phosphor.bloomRadius,
                                        height: settings.phosphor.bloomRadius),
                isEnabled: settings.enabled && settings.phosphor.bloomStrength != 0)
            .colorEffect(
                DrumBundle.shaders.crtMask(
                    .boundingRect,
                    .float(settings.scale),
                    .float(settings.scanlines),
                    .float(settings.grille),
                    .float(settings.vignette),
                    .float(settings.brightness),
                    .color(settings.phosphor.swiftUIColor)),
                isEnabled: settings.enabled)
            .distortionEffect(
                DrumBundle.shaders.crtBarrel(
                    .boundingRect,
                    .float(settings.barrelX),
                    .float(settings.barrelY),
                    .float(settings.isWobbling ? settings.wobble : 0),
                    .float(Float(time.truncatingRemainder(dividingBy: Self.timePeriod)))),
                maxSampleOffset: CGSize(width: 160, height: 60),
                isEnabled: settings.enabled)
            .clipShape(RoundedRectangle(cornerRadius: settings.bezelCornerRadius, style: .continuous))
            .background(Color.black)
    }
}

extension View {
    func crt(_ settings: CRTSettings, time: TimeInterval, liveResize: Bool = false) -> some View {
        modifier(CRTEffect(settings: settings, time: time, liveResize: liveResize))
    }
}
