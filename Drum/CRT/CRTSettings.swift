import Foundation

/// Every uniform the CRT chain takes, plus the two switches that bypass it.
/// Persisted as JSON by `AppState`; every field has a Settings slider.
///
/// Decoding tolerates missing keys (new fields get their defaults) so adding a
/// uniform never wipes a user's tuning.
struct CRTSettings: Codable, Sendable, Equatable {
    var enabled = true
    var phosphor: Phosphor = .p3Amber
    var barrelX: Float = 0.02
    var barrelY: Float = 0.02
    var wobble: Float = 0.0015
    var scanlines: Float = 0.15
    var grille: Float = 0.04
    var vignette: Float = 0.25
    /// Gain applied in the mask pass so the phosphor reads bright through the
    /// scanlines and grille. Above 1 the core of a glyph clips toward white,
    /// which is what a hot phosphor looks like.
    var brightness: Float = 1.45
    /// `backingScaleFactor` of the screen the window is on. Scanline period
    /// is in device pixels, so the shader needs this. Set by `ScreenPinning`.
    var scale: Float = 1
    var animated = true
    var bezelCornerRadius: CGFloat = 42

    /// Tuning for the 32:9 panel per spec §4: less horizontal curvature.
    static let ribbon: CRTSettings = {
        var s = CRTSettings()
        s.barrelX = 0.015
        s.barrelY = 0.03
        return s
    }()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, phosphor, barrelX, barrelY, wobble, scanlines, grille, vignette
        case brightness, scale, animated, bezelCornerRadius
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CRTSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        phosphor = try c.decodeIfPresent(Phosphor.self, forKey: .phosphor) ?? d.phosphor
        barrelX = try c.decodeIfPresent(Float.self, forKey: .barrelX) ?? d.barrelX
        barrelY = try c.decodeIfPresent(Float.self, forKey: .barrelY) ?? d.barrelY
        wobble = try c.decodeIfPresent(Float.self, forKey: .wobble) ?? d.wobble
        scanlines = try c.decodeIfPresent(Float.self, forKey: .scanlines) ?? d.scanlines
        grille = try c.decodeIfPresent(Float.self, forKey: .grille) ?? d.grille
        vignette = try c.decodeIfPresent(Float.self, forKey: .vignette) ?? d.vignette
        brightness = try c.decodeIfPresent(Float.self, forKey: .brightness) ?? d.brightness
        scale = try c.decodeIfPresent(Float.self, forKey: .scale) ?? d.scale
        animated = try c.decodeIfPresent(Bool.self, forKey: .animated) ?? d.animated
        bezelCornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .bezelCornerRadius) ?? d.bezelCornerRadius
    }
}
