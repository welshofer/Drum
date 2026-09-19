import CoreGraphics
import Foundation

/// Compare displayed colors, not storage byte order or source color-space tags.
enum CapturePixels {
    static func matches(_ actual: CGImage, _ expected: CGImage, tolerance: Int = 0) -> Bool {
        guard actual.width == expected.width, actual.height == expected.height else { return false }
        let a = rgba(actual)
        let b = rgba(expected)
        var maximum = 0
        var changed = 0
        for (left, right) in zip(a, b) {
            let difference = abs(Int(left) - Int(right))
            maximum = max(maximum, difference)
            if difference != 0 { changed += 1 }
        }
        if maximum > tolerance {
            print("Capture pixel difference: maximum=\(maximum), changed=\(changed)/\(a.count)")
        }
        return maximum <= tolerance
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                         count: image.width * image.height * 4))
    }
}
