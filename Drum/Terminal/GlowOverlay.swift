import SwiftUI

/// Spec §5.1 option 1: rows that just changed get an overbright, slightly
/// blurred flash for 80 ms so fresh text reads as a phosphor hit. Sits on top
/// of the terminal, inside the CRT chain, so the bloom picks it up too.
struct GlowOverlay: View {
    let session: TerminalSession
    let phosphor: Phosphor

    var body: some View {
        let flashes = session.flashes
        let rowHeight = session.view.rowHeight
        TimelineView(.animation(minimumInterval: 1 / 60, paused: flashes.isEmpty)) { context in
            let now = context.date
            let bands = Self.bands(flashes: flashes, now: now, rowHeight: rowHeight)
            Canvas { gc, size in
                for band in bands {
                    let rect = CGRect(x: 0, y: band.y, width: size.width, height: rowHeight)
                    gc.fill(Path(rect), with: .color(phosphor.swiftUIColor.opacity(0.4 * band.alpha)))
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
