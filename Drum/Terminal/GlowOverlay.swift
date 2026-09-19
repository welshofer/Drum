import SwiftUI

/// A masked copy of the picture gives newly changed rows their 80 ms flash.
/// Uses the CRT stage's clock so glow and wobble share one animation timeline.
struct GlowOverlay: View {
    let session: TerminalSession
    let date: Date

    var body: some View {
        let rowHeight = session.view.rowHeight
        let bands = Self.bands(flashes: session.flashes, now: date, rowHeight: rowHeight)
        let mirror = session.mirror
        if let image = mirror.image, !bands.isEmpty {
            Image(decorative: image, scale: mirror.scale)
                .mask {
                    Canvas { gc, size in
                        for band in bands {
                            let rect = CGRect(x: 0, y: band.y, width: size.width, height: rowHeight)
                            gc.fill(Path(rect), with: .color(.white.opacity(0.45 * band.alpha)))
                        }
                    }
                }
                .blur(radius: 0.6)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }

    struct Band {
        let y: CGFloat
        let alpha: Double
    }

    static func bands(flashes: [Int: Date], now: Date, rowHeight: CGFloat) -> [Band] {
        guard rowHeight > 0 else { return [] }
        return flashes.compactMap { row, arrived in
            let age = now.timeIntervalSince(arrived)
            guard age >= 0, age < TerminalSession.flashDuration else { return nil }
            return Band(y: CGFloat(row) * rowHeight, alpha: 1 - age / TerminalSession.flashDuration)
        }
    }
}
