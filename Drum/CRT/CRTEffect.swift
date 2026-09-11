import SwiftUI

/// The modifier chain. Order is load-bearing: bloom → mask → barrel → bezel.
/// Bloom runs before the barrel so the glow curves with the glass.
/// Applied once, on the terminal container. Never on the window.
struct CRTEffect: ViewModifier {
    let settings: CRTSettings
    let time: TimeInterval

    func body(content: Content) -> some View {
        content
            .layerEffect(
                DrumBundle.shaders.crtBloom(
                    .float(settings.phosphor.bloomRadius),
                    .float(settings.phosphor.bloomStrength),
                    .color(settings.phosphor.swiftUIColor)),
                maxSampleOffset: CGSize(width: settings.phosphor.bloomRadius,
                                        height: settings.phosphor.bloomRadius),
                isEnabled: settings.enabled)
            .colorEffect(
                DrumBundle.shaders.crtMask(
                    .boundingRect,
                    .float(settings.scale),
                    .float(settings.scanlines),
                    .float(settings.grille),
                    .float(settings.vignette),
                    .float(settings.brightness)),
                isEnabled: settings.enabled)
            .distortionEffect(
                DrumBundle.shaders.crtBarrel(
                    .boundingRect,
                    .float(settings.barrelX),
                    .float(settings.barrelY),
                    .float(settings.animated ? settings.wobble : 0),
                    .float(Float(time))),
                maxSampleOffset: CGSize(width: 160, height: 60),
                isEnabled: settings.enabled)
            .clipShape(RoundedRectangle(cornerRadius: settings.bezelCornerRadius, style: .continuous))
            .background(Color.black)
    }
}

extension View {
    func crt(_ settings: CRTSettings, time: TimeInterval) -> some View {
        modifier(CRTEffect(settings: settings, time: time))
    }
}
