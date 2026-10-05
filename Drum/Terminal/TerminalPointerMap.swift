import AppKit

/// Matches crtBarrel's output-to-source mapping. The input host is inset but
/// the shader covers the entire stage; both use the same frame's uniforms.
@MainActor
struct TerminalPointerMap: Equatable {
    let settings: CRTSettings
    let time: TimeInterval

    func sourcePoint(_ point: CGPoint, terminalSize: CGSize) -> CGPoint {
        guard settings.enabled, terminalSize.width > 0, terminalSize.height > 0 else { return point }
        let inset = CRTStage.inset
        let width = Float(terminalSize.width + inset.leading + inset.trailing)
        let height = Float(terminalSize.height + inset.top + inset.bottom)
        let u = Float(point.x + inset.leading) / width
        let row = Float(terminalSize.height - point.y + inset.top)
        let v = row / height
        var x = u * 2 - 1
        var y = v * 2 - 1
        let radiusSquared = x * x + y * y
        x *= 1 + settings.barrelX * radiusSquared
        y *= 1 + settings.barrelY * radiusSquared
        if settings.isWobbling {
            let t = Float(time.truncatingRemainder(dividingBy: CRTEffect.timePeriod))
            let noise = Self.syncNoise(row: row, time: t)
            x += settings.wobble * (0.6 * sin(t * 1.7 + v * 9) + 0.4 * (noise - 0.5))
        }
        return CGPoint(x: CGFloat((x + 1) * 0.5 * width) - inset.leading,
                       y: terminalSize.height - (CGFloat((y + 1) * 0.5 * height) - inset.top))
    }

    private static func syncNoise(row: Float, time: Float) -> Float {
        var n = UInt32(min(65_535, max(0, floor(row))))
            ^ (UInt32(floor(max(time, 0) * 60)) &* 747_796_405) ^ 2_891_336_453
        n ^= n >> 16; n &*= 2_246_822_519
        n ^= n >> 13; n &*= 3_266_489_917
        n ^= n >> 16
        return Float(n >> 8) / 16_777_216
    }
}
