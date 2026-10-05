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
    /// is in device pixels, so the shader needs this. Supplied by the view at render time.
    var scale: Float = 1
    var animated = true
    var bezelCornerRadius: CGFloat = 42

    /// Only the sync wobble needs continuous animation.
    var isWobbling: Bool { enabled && animated && wobble != 0 }

    /// Persisted values must obey the same limits as the appearance controls.
    /// Invalid fields get their defaults; valid tuning and switches survive.
    var normalized: Self {
        var result = self
        let defaults = Self()
        result.phosphor = phosphor.normalized
        result.barrelX = Self.validated(barrelX, in: 0...0.15, default: defaults.barrelX)
        result.barrelY = Self.validated(barrelY, in: 0...0.15, default: defaults.barrelY)
        result.wobble = Self.validated(wobble, in: 0...0.01, default: defaults.wobble)
        result.scanlines = Self.validated(scanlines, in: 0...0.5, default: defaults.scanlines)
        result.grille = Self.validated(grille, in: 0...0.3, default: defaults.grille)
        result.vignette = Self.validated(vignette, in: 0...1.5, default: defaults.vignette)
        result.brightness = Self.validated(brightness, in: 0.5...2, default: defaults.brightness)
        result.bezelCornerRadius = Self.validated(bezelCornerRadius, in: 0...120, default: defaults.bezelCornerRadius)
        // Backing scale comes from the display at rendering time, never storage.
        result.scale = defaults.scale
        return result
    }

    static func validated<Value: BinaryFloatingPoint>(
        _ value: Value, in range: ClosedRange<Value>, default fallback: Value
    ) -> Value {
        value.isFinite && range.contains(value) ? value : fallback
    }

    /// Transient rendering policy; never written back to the user's settings.
    func forRendering(scale: Float, liveResize: Bool) -> Self {
        var result = self
        result.scale = scale
        if liveResize { result.animated = false }
        return result
    }

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
        // Decode through Double so even finite JSON beyond Float's capacity
        // defaults just that field rather than discarding the entire record.
        func number(_ key: CodingKeys, default fallback: Double) throws -> Double {
            try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
        }
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        phosphor = try c.decodeIfPresent(Phosphor.self, forKey: .phosphor) ?? d.phosphor
        barrelX = Float(try number(.barrelX, default: Double(d.barrelX)))
        barrelY = Float(try number(.barrelY, default: Double(d.barrelY)))
        wobble = Float(try number(.wobble, default: Double(d.wobble)))
        scanlines = Float(try number(.scanlines, default: Double(d.scanlines)))
        grille = Float(try number(.grille, default: Double(d.grille)))
        vignette = Float(try number(.vignette, default: Double(d.vignette)))
        brightness = Float(try number(.brightness, default: Double(d.brightness)))
        scale = d.scale
        animated = try c.decodeIfPresent(Bool.self, forKey: .animated) ?? d.animated
        bezelCornerRadius = CGFloat(try number(.bezelCornerRadius, default: Double(d.bezelCornerRadius)))
        self = normalized
    }
}
