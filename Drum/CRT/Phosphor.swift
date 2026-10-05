import SwiftUI

/// One phosphor: the tube colour plus how much it glows.
///
/// Colour is stored as three sRGB floats rather than a SwiftUI `Color` so the
/// struct is `Codable` with an exact round trip; `swiftUIColor` and `nsColor`
/// convert at the edges.
struct Phosphor: Codable, Sendable, Equatable {
    var red: Float
    var green: Float
    var blue: Float
    var bloomRadius: CGFloat
    var bloomStrength: Float

    static let p1Green = Phosphor(red: 0.36, green: 1.00, blue: 0.40, bloomRadius: 3.5, bloomStrength: 0.7)
    static let p3Amber = Phosphor(red: 1.00, green: 0.69, blue: 0.16, bloomRadius: 2.5, bloomStrength: 0.75)
    static let p4White = Phosphor(red: 0.86, green: 0.92, blue: 1.00, bloomRadius: 2.0, bloomStrength: 0.5)

    /// Storage recovery defaults invalid fields without changing valid custom colours.
    var normalized: Self {
        let defaults = Self.p3Amber
        return Phosphor(
            red: CRTSettings.validated(red, in: 0...1, default: defaults.red),
            green: CRTSettings.validated(green, in: 0...1, default: defaults.green),
            blue: CRTSettings.validated(blue, in: 0...1, default: defaults.blue),
            bloomRadius: CRTSettings.validated(bloomRadius, in: 0...8, default: defaults.bloomRadius),
            bloomStrength: CRTSettings.validated(bloomStrength, in: 0...2, default: defaults.bloomStrength)
        )
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: Double(red), green: Double(green), blue: Double(blue), opacity: 1)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1)
    }

    /// The phosphor scaled to a brightness step in `0...1` (monochrome tube).
    func nsColor(brightness: Double) -> NSColor {
        let b = CGFloat(min(max(brightness, 0), 1))
        return NSColor(srgbRed: CGFloat(red) * b, green: CGFloat(green) * b, blue: CGFloat(blue) * b, alpha: 1)
    }

    /// Replace the tint, keeping the bloom numbers. `Color.Resolved` is
    /// extended-range sRGB, so a saturated pick can come back below 0 or above
    /// 1; everything downstream (16-bit palette, NSColor) needs `0...1`.
    mutating func setColor(_ resolved: Color.Resolved) {
        red = Self.unit(resolved.red)
        green = Self.unit(resolved.green)
        blue = Self.unit(resolved.blue)
    }

    static func unit(_ value: Float) -> Float {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    /// The phosphor with every component forced into `0...1`, for values that
    /// were persisted before clamping existed.
    var clamped: Phosphor {
        var p = self
        p.red = Self.unit(red)
        p.green = Self.unit(green)
        p.blue = Self.unit(blue)
        return p
    }
}

extension Phosphor {
    private enum CodingKeys: String, CodingKey {
        case red, green, blue, bloomRadius, bloomStrength
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.p3Amber
        func number(_ key: CodingKeys, default fallback: Double) -> Double {
            (try? c.decodeIfPresent(Double.self, forKey: key)) ?? fallback
        }
        red = Float(number(.red, default: Double(defaults.red)))
        green = Float(number(.green, default: Double(defaults.green)))
        blue = Float(number(.blue, default: Double(defaults.blue)))
        bloomRadius = CGFloat(number(.bloomRadius, default: Double(defaults.bloomRadius)))
        bloomStrength = Float(number(.bloomStrength, default: Double(defaults.bloomStrength)))
        self = normalized
    }
}

/// The Settings picker choices. `.custom` keeps whatever colour the user picked.
enum PhosphorPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case amber, green, white, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amber: "Amber (P3)"
        case .green: "Green (P1)"
        case .white: "White (P4)"
        case .custom: "Custom"
        }
    }

    /// The preset phosphor, or `nil` for `.custom`.
    var phosphor: Phosphor? {
        switch self {
        case .amber: .p3Amber
        case .green: .p1Green
        case .white: .p4White
        case .custom: nil
        }
    }
}
