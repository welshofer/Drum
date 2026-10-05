import SwiftUI

/// Power-on: a bright flyback line collapses to a dot over black, then the
/// picture opens from the centre. Power-off is the same thing backwards.
///
/// `progress` is 0 fully off and 1 fully on; the transition animates it and
/// `PowerOnModifier` turns it into the flyback overlay plus the picture reveal.
struct PowerOnTransition: Transition {
    var tint: Color
    var reduceMotion = false

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(PowerOnModifier(progress: phase.isIdentity ? 1 : 0, tint: tint, reduceMotion: reduceMotion))
    }

    static let onDuration: TimeInterval = 0.7
    static let offDuration: TimeInterval = 0.3

    /// 700 ms on, 300 ms off, per spec §6.
    static func asymmetric(tint: Color, reduceMotion: Bool = false) -> some Transition {
        AsymmetricTransition(
            insertion: PowerOnTransition(tint: tint, reduceMotion: reduceMotion)
                .animation(.easeOut(duration: reduceMotion ? 0.15 : onDuration)),
            removal: PowerOnTransition(tint: tint, reduceMotion: reduceMotion)
                .animation(.easeIn(duration: reduceMotion ? 0.15 : offDuration)))
    }
}

/// `ViewModifier` conformance makes the type main-actor isolated; `Animatable`
/// is not, and SwiftUI drives `animatableData` from its own machinery, so the
/// animated storage is `nonisolated` (SE-0434: Sendable stored properties of
/// isolated value types may be).
struct PowerOnModifier: ViewModifier, Animatable {
    nonisolated var progress: Double
    nonisolated var tint: Color
    nonisolated var reduceMotion = false

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// The picture opens vertically from the centre during the second half.
    private var pictureScaleY: CGFloat {
        let t = min(max((progress - 0.45) / 0.55, 0), 1)
        return 0.02 + 0.98 * CGFloat(t * t)
    }

    private var pictureOpacity: Double {
        min(max((progress - 0.5) / 0.4, 0), 1)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1, y: reduceMotion ? 1 : pictureScaleY, anchor: .center)
            .opacity(reduceMotion ? progress : pictureOpacity)
            .overlay {
                Rectangle()
                    .fill(Color.black)
                    .colorEffect(DrumBundle.shaders.crtFlyback(.boundingRect, .float(Float(progress)), .color(tint)),
                                 isEnabled: !reduceMotion)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .opacity(!reduceMotion && progress < 1 ? 1 : 0)
            }
    }
}
