import SwiftUI

/// Spec §5.1 option 1: rows that just changed get an overbright, slightly
/// blurred flash for 80 ms so fresh text reads as a phosphor hit.
///
/// The flash is a second copy of the mirrored picture, masked to the changed
/// rows and added with `.plusLighter`: only lit pixels (glyphs) brighten,
/// black cells stay black, so a whole-screen redraw is a brief brightening of
/// the text rather than an amber wall. Sits inside the CRT chain so the bloom
/// picks it up too.
struct GlowOverlay: View {
    let session: TerminalSession
    let phosphor: Phosphor

    var body: some View {
        let flashes = session.flashes
        let rowHeight = session.view.rowHeight
        let mirror = session.mirror
        TimelineView(.animation(minimumInterval: 1 / 60, paused: flashes.isEmpty)) { context in
            let bands = Self.bands(flashes: flashes, now: context.date, rowHeight: rowHeight)
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
