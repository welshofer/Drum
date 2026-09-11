import Foundation

/// Every uniform the CRT chain takes, plus the two switches that bypass it.
/// Persisted as JSON by `AppState`; every field has a Settings slider.
struct CRTSettings: Codable, Sendable, Equatable {
    var enabled = true
    var phosphor: Phosphor = .p3Amber
    var barrelX: Float = 0.05
    var barrelY: Float = 0.05
    var wobble: Float = 0.0015
    var scanlines: Float = 0.28
    var grille: Float = 0.08
    var vignette: Float = 0.35
    /// `backingScaleFactor` of the screen the window is on. Scanline period
    /// is in device pixels, so the shader needs this. Set by `ScreenPinning`.
    var scale: Float = 1
    var animated = true
    var bezelCornerRadius: CGFloat = 42

    /// Tuning for the 32:9 panel per spec §4: less horizontal curvature.
    static let ribbon: CRTSettings = {
        var s = CRTSettings()
        s.barrelX = 0.03
        s.barrelY = 0.06
        return s
    }()
}
