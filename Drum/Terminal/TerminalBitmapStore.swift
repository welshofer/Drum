import AppKit

/// Two reusable backing stores. Each remembers all damage since it was last
/// displayed, so alternating buffers never resurrects an older line of text.
@MainActor
final class TerminalBitmapStore {
    private struct Slot {
        var rep: NSBitmapImageRep?
        var damage: [CGRect] = []
        var redrawAll = true
    }

    private var slots = [Slot(), Slot()]
    private var index = 0
    private var bounds = CGRect.zero
    private var scale: CGFloat = 0
    private(set) var allocationCount = 0
    private(set) var lastDrawnRects: [CGRect] = []
    var lastDrawnRect: CGRect { lastDrawnRects.reduce(CGRect.null) { $0.union($1) } }
    var lastDrawnArea: CGFloat { lastDrawnRects.reduce(0) { $0 + $1.width * $1.height } }

    func invalidate(_ rect: CGRect? = nil) {
        for i in slots.indices {
            guard !slots[i].redrawAll else { continue }
            if let rect {
                Self.add(rect, to: &slots[i].damage)
                // Bound bookkeeping for highly fragmented output.
                if slots[i].damage.count <= 16 { continue }
            }
            slots[i].damage.removeAll(keepingCapacity: true)
            slots[i].redrawAll = true
        }
    }

    func capture(_ view: NSView, scale: CGFloat, liveResize: Bool) -> CGImage? {
        let bounds = view.bounds
        guard scale > 0, bounds.width >= 1, bounds.height >= 1 else { return nil }
        let width = Int(ceil(bounds.width * scale))
        let height = Int(ceil(bounds.height * scale))
        let scaleChanged = self.scale != scale
        if self.bounds != bounds || scaleChanged {
            self.bounds = bounds
            self.scale = scale
            invalidate()
        }

        // Keep spare capacity during a drag. Afterward return to exact size.
        let capacityWidth = liveResize ? Self.capacity(for: width) : width
        let capacityHeight = liveResize ? Self.capacity(for: height) : height
        for i in slots.indices {
            let rep = slots[i].rep
            let fits = rep.map {
                liveResize
                    ? $0.pixelsWide >= width && $0.pixelsHigh >= height
                    : $0.pixelsWide == width && $0.pixelsHigh == height
            } ?? false
            if !fits || scaleChanged {
                slots[i].rep = Self.makeBitmap(width: capacityWidth, height: capacityHeight, scale: scale)
                slots[i].damage.removeAll(keepingCapacity: true)
                slots[i].redrawAll = true
                allocationCount += 1
            }
        }

        let next = (index + 1) % slots.count
        guard let rep = slots[next].rep,
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let damage = slots[next].redrawAll ? [bounds] : slots[next].damage
        // Align outwards to device pixels; the terminal supplies glyph-safe
        // dirty rectangles, including dependencies between double-height rows.
        var drawRects: [CGRect] = []
        for region in damage {
            let damage = region.intersection(bounds)
            guard !damage.isNull, !damage.isEmpty else { continue }
            let pixels = CGRect(x: damage.minX * scale, y: damage.minY * scale,
                                width: damage.width * scale, height: damage.height * scale).integral
            let drawRect = CGRect(x: pixels.minX / scale, y: pixels.minY / scale,
                              width: pixels.width / scale, height: pixels.height / scale)
                .intersection(bounds)
            Self.add(drawRect, to: &drawRects)
        }
        if drawRects.reduce(0, { $0 + $1.width * $1.height }) >= bounds.width * bounds.height * 0.65 {
            drawRects = [bounds]
        }
        for drawRect in drawRects {
            // Unlike cacheDisplay(in:to:), this preserves the dirty rectangle's
            // origin in the backing store instead of moving it to (0, 0).
            context.cgContext.saveGState()
            context.cgContext.clip(to: drawRect)
            context.cgContext.clear(drawRect)
            view.displayIgnoringOpacity(drawRect, in: context)
            context.cgContext.restoreGState()
        }
        guard let image = rep.cgImage?.cropping(to: CGRect(
            x: 0, y: rep.pixelsHigh - height, width: width, height: height)) else { return nil }
        slots[next].damage.removeAll(keepingCapacity: true)
        slots[next].redrawAll = false
        lastDrawnRects = drawRects
        index = next
        return image
    }

    /// AppKit's caching-display factory uses Generic RGB. SwiftUI then converts
    /// every published frame on the CPU. Draw into sRGB from the start, in the
    /// premultiplied RGBA format. Tag the empty buffer before drawing so AppKit
    /// performs real color conversion, not retagging
    /// already-rendered pixels (which would change their appearance).
    private static func makeBitmap(width: Int, height: Int, scale: CGFloat) -> NSBitmapImageRep? {
        guard let storage = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bitmapFormat: [],
                                             bytesPerRow: 0, bitsPerPixel: 32),
              let rep = storage.retagging(with: .sRGB) else { return nil }
        rep.size = CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        return rep
    }

    /// Merge only when the bounding box costs no more than drawing separately.
    /// In particular, a narrow scrollbar must not expand a row update to the
    /// entire viewport. Overlapping regions are safe: each is cleared and drawn.
    private static func add(_ rect: CGRect, to regions: inout [CGRect]) {
        guard !rect.isNull, !rect.isEmpty, !rect.isInfinite else { return }
        var merged = rect
        var i = 0
        while i < regions.count {
            let other = regions[i]
            let union = merged.union(other)
            if union.width * union.height <= merged.width * merged.height + other.width * other.height {
                merged = union
                regions.remove(at: i)
                i = 0
            } else {
                i += 1
            }
        }
        regions.append(merged)
    }

    private static func capacity(for pixels: Int) -> Int {
        ((pixels + 255) / 256) * 256
    }
}
