import AppKit
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalBitmapStoreTests {
    @Test(arguments: [CGFloat(1), CGFloat(2)])
    func partialRedrawsMatchFullCapturesAndPreservePublishedImages(scale: CGFloat) throws {
        let view = PatternView(scale: scale)
        let store = TerminalBitmapStore()
        let original = try #require(store.capture(view, scale: scale, liveResize: false))
        let originalPixels = pixels(original)
        _ = store.capture(view, scale: scale, liveResize: false)

        // These changes land in alternating buffers. Each must include damage
        // from the intervening frame as well as the current frame.
        for row in [0, 1, 2, 1, 2, 3] {
            view.rows[row] = view.rows[row] == .red ? .blue : .red
            let rect = CGRect(x: 0, y: CGFloat(row) * 10, width: view.bounds.width, height: 10)
            store.invalidate(rect)
            let image = try #require(store.capture(view, scale: scale, liveResize: false))
            #expect(pixels(image) == pixels(try reference(view)))
            #expect(pixels(original) == originalPixels)
            #expect(store.lastDrawnRect.height < view.bounds.height)
        }
        #expect(store.allocationCount == 2)
    }

    @Test(arguments: [CGFloat(1), CGFloat(2)])
    func liveResizeReusesCapacityAndCropsWithoutStretching(scale: CGFloat) throws {
        let view = PatternView(scale: scale)
        let store = TerminalBitmapStore()
        for width in 41...80 {
            view.setFrameSize(CGSize(width: width, height: 40 + width % 9))
            let image = try #require(store.capture(view, scale: scale, liveResize: true))
            #expect(image.width == width * Int(scale))
            #expect(image.height == Int(view.bounds.height * scale))
            #expect(pixels(image) == pixels(try reference(view)))
        }
        #expect(store.allocationCount == 2)
        let settled = try #require(store.capture(view, scale: scale, liveResize: false))
        #expect(pixels(settled) == pixels(try reference(view)))
        #expect(store.allocationCount == 4)
    }

    @Test func scaleAndFullInvalidationsReplaceEveryPixel() throws {
        let view = PatternView(scale: 1)
        let store = TerminalBitmapStore()
        _ = store.capture(view, scale: 1, liveResize: false)
        _ = store.capture(view, scale: 1, liveResize: false)
        view.testScale = 2
        let image = try #require(store.capture(view, scale: 2, liveResize: false))
        #expect(image.width == 80 && image.height == 80)
        #expect(pixels(image) == pixels(try reference(view)))
        view.rows = [.green, .green, .green, .green]
        store.invalidate()
        for _ in 0..<2 {
            let refreshed = try #require(store.capture(view, scale: 2, liveResize: false))
            #expect(pixels(refreshed) == pixels(try reference(view)))
        }
    }

    @Test func erasingTextClearsOldPixelsAndOutsideDamageIsHarmless() throws {
        let view = PatternView(scale: 2)
        let store = TerminalBitmapStore()
        _ = store.capture(view, scale: 2, liveResize: false)
        _ = store.capture(view, scale: 2, liveResize: false)
        view.rows[1] = .clear
        store.invalidate(CGRect(x: 0, y: 10, width: 40, height: 10))
        _ = store.capture(view, scale: 2, liveResize: false)
        let image = try #require(store.capture(view, scale: 2, liveResize: false))
        #expect(pixels(image) == pixels(try reference(view)))
        store.invalidate(CGRect(x: 100, y: 100, width: 10, height: 10))
        let unchanged = try #require(store.capture(view, scale: 2, liveResize: false))
        #expect(pixels(unchanged) == pixels(image))
    }

    @Test(arguments: [CGFloat(1), CGFloat(2)])
    func distantRowsAndScrollbarKeepIndependentDamage(scale: CGFloat) throws {
        let view = PatternView(scale: scale)
        let store = TerminalBitmapStore()
        _ = store.capture(view, scale: scale, liveResize: false)
        _ = store.capture(view, scale: scale, liveResize: false)
        view.rows[0] = .blue
        view.rows[3] = .red
        store.invalidate(CGRect(x: 0, y: 0, width: 40, height: 10))
        store.invalidate(CGRect(x: 0, y: 30, width: 40, height: 10))
        for _ in 0..<2 {
            let image = try #require(store.capture(view, scale: scale, liveResize: false))
            #expect(pixels(image) == pixels(try reference(view)))
            #expect(store.lastDrawnRects.count == 2)
            #expect(store.lastDrawnArea == 800, "Untouched middle rows must not be redrawn")
        }
        view.rows[1] = .clear
        view.stripe = .magenta
        store.invalidate(CGRect(x: 0, y: 10, width: 40, height: 10))
        store.invalidate(CGRect(x: 3, y: 0, width: 2, height: 40))
        for _ in 0..<2 {
            let image = try #require(store.capture(view, scale: scale, liveResize: false))
            #expect(pixels(image) == pixels(try reference(view)))
            #expect(store.lastDrawnRects.count == 2)
            #expect(store.lastDrawnArea == 480, "A scrollbar crossing a row must not dirty the full view")
        }
    }

    @Test func fragmentedAndDenseDamageFallBackToFullRedraw() throws {
        let view = PatternView(scale: 1)
        let store = TerminalBitmapStore()
        _ = store.capture(view, scale: 1, liveResize: false)
        _ = store.capture(view, scale: 1, liveResize: false)
        for y in 0..<4 {
            for x in 0..<5 {
                store.invalidate(CGRect(x: x * 8, y: y * 10, width: 1, height: 1))
            }
        }
        _ = store.capture(view, scale: 1, liveResize: false)
        #expect(store.lastDrawnRects == [view.bounds])
        _ = store.capture(view, scale: 1, liveResize: false)
        store.invalidate(CGRect(x: 0, y: 0, width: 40, height: 30))
        _ = store.capture(view, scale: 1, liveResize: false)
        #expect(store.lastDrawnRects == [view.bounds])
    }

    private func reference(_ view: NSView) throws -> CGImage {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return try #require(rep.cgImage)
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        // Cropped images may retain the larger backing store's row stride.
        let data = image.dataProvider!.data! as Data
        let bytesPerPixel = image.bitsPerPixel / 8
        return (0..<image.height).flatMap { row in
            Array(data[(row * image.bytesPerRow)..<(row * image.bytesPerRow + image.width * bytesPerPixel)])
        }
    }
}

@MainActor
private final class PatternView: NSView {
    var rows: [NSColor] = [.red, .green, .blue, .white]
    var stripe: NSColor = .yellow
    var testScale: CGFloat

    init(scale: CGFloat) {
        testScale = scale
        super.init(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func bitmapImageRepForCachingDisplay(in rect: NSRect) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                  pixelsWide: Int(ceil(rect.width * testScale)),
                                  pixelsHigh: Int(ceil(rect.height * testScale)),
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 32)
        rep?.size = rect.size
        return rep
    }

    override func draw(_ dirtyRect: NSRect) {
        for (row, color) in rows.enumerated() {
            color.setFill()
            CGRect(x: 0, y: CGFloat(row) * 10, width: bounds.width, height: 10).fill()
        }
        // A narrow stripe exposes accidental scaling and horizontal offsets.
        stripe.setFill()
        CGRect(x: 3, y: 0, width: 2, height: bounds.height).fill()
    }
}
