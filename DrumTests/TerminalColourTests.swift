import AppKit
import Metal
import SwiftTerm
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalColourTests {
    @Test func colourModeDefaultsAndRoundTripsWithoutLosingTuning() throws {
        for mode in ["", ",\"colourMode\":\"futureMode\"", ",\"colourMode\":42"] {
            let data = Data("{\"barrelX\":0.08,\"brightness\":1.2\(mode)}".utf8)
            let restored = try JSONDecoder().decode(CRTSettings.self, from: data)
            #expect(restored.colourMode == .monochrome)
            #expect(restored.barrelX == 0.08 && restored.brightness == 1.2)
        }
        let domain = "drum.colour.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let state = AppState(defaults: defaults)
        state.crt.colourMode = .preserveColours
        state.crt.wobble = 0.006
        let restored = AppState(defaults: defaults)
        #expect(restored.crt == state.crt)
        #expect(TerminalTheme(state: restored).colourMode == .preserveColours)
        #expect(restored.crt.forRendering(scale: 2, liveResize: true, reduceMotion: true).colourMode == .preserveColours)
        let data = try #require(defaults.data(forKey: "drum.crt.v3"))
        #expect(String(decoding: data, as: UTF8.self).contains("preserveColours"))
    }

    @Test func installedANSIPaletteChangesWithoutResettingNativeTerminalState() throws {
        let view = PaletteProbeView(frame: CGRect(x: 0, y: 0, width: 640, height: 240))
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let mono = TerminalTheme(font: font, phosphor: .p3Amber)
        let colour = TerminalTheme(font: font, phosphor: .p3Amber, colourMode: .preserveColours)
        mono.apply(to: view, previous: nil)
        view.feed(text: "ANSI colour mode\r\n\u{1B}[38;2;12;34;56mT")
        let engine = view.getTerminal()
        let cursor = Position(col: engine.buffer.x, row: engine.buffer.y)
        view.selection.setSelection(start: Position(col: 0, row: 0), end: Position(col: 4, row: 0))
        let selected = view.selection.getSelectedText()
        #expect(selected == "ANSI")
        for (theme, previous) in [(colour, mono), (mono, colour), (colour, mono)] {
            theme.apply(to: view, previous: previous)
            for slot in 0..<16 {
                let expected = theme.palette[slot]
                view.replies = []
                view.feed(text: "\u{1B}]4;\(slot);?\u{7}")
                let rgb = String(format: "rgb:%04x/%04x/%04x", Int(expected.red), Int(expected.green), Int(expected.blue))
                #expect(String(decoding: view.replies, as: UTF8.self).contains("4;\(slot);\(rgb)"))
            }
            #expect(view.getTerminal() === engine && view.font == font)
            #expect(engine.buffer.x == cursor.col && engine.buffer.y == cursor.row)
            #expect(view.selection.getSelectedText() == selected)
            #expect(engine.getCharData(col: 0, row: 1)?.attribute.fg == .trueColor(red: 12, green: 34, blue: 56))
        }
        let palette = colour.palette
        #expect(palette[1].red > palette[1].green && palette[1].red > palette[1].blue)
        #expect(palette[2].green > palette[2].red && palette[2].green > palette[2].blue)
        #expect(palette[4].blue > palette[4].red && palette[4].blue > palette[4].green)
        let originalRed = SwiftTerm.Color.xtermColors[1].red
        palette[1].red = 0
        #expect(SwiftTerm.Color.xtermColors[1].red == originalRed)
    }

    @Test func actualMetalMaskPreservesHueAlphaAndCRTEffects() throws {
        let gpu = try ColourShaderProbe()
        for input in [SIMD4<Float>(0.5, 0, 0, 0.7), SIMD4(0, 0.4, 0, 0.6),
                      SIMD4(0, 0, 0.3, 0.5), SIMD4(0.2, 0.4, 0.6, 0.75), .zero] {
            let result = try gpu.sample(input: input).mask
            #expect(close(result, input))
            let dimmed = try gpu.sample(input: input, brightness: 0.5).mask
            #expect(close(SIMD3(dimmed.x, dimmed.y, dimmed.z), SIMD3(input.x, input.y, input.z) * 0.5))
            #expect(abs(dimmed.w - input.w) < 0.001)
        }
        let input = SIMD4<Float>(0.2, 0.4, 0.6, 0.75)
        let even = try gpu.sample(input: input, position: SIMD2(50.5, 50.25), scanlines: 0.5).mask
        let odd = try gpu.sample(input: input, position: SIMD2(50.5, 51.25), scanlines: 0.5).mask
        #expect(odd.x < even.x && odd.y < even.y && odd.z < even.z && odd.w == even.w)
        let grille = try gpu.sample(input: input, position: SIMD2(51.5, 50.5), grille: 0.3).mask
        #expect(abs(grille.x - input.x) < 0.001 && grille.y < input.y && grille.z < input.z)
        let centre = try gpu.sample(input: input, vignette: 1).mask
        let edge = try gpu.sample(input: input, position: SIMD2(0.5, 50.5), vignette: 1).mask
        #expect(edge.x < centre.x && edge.y < centre.y && edge.z < centre.z && edge.w == centre.w)
        let mono = try gpu.sample(input: SIMD4(0, 0, 0.5, 0.75), preserve: false).mask
        #expect(mono.x > 0 && abs(mono.y / mono.x - 0.5) < 0.002 && mono.z == 0 && mono.w == 0.75)
    }

    @Test func actualMetalBloomAddsRGBWithoutTintLeakOrInvalidAlpha() throws {
        let gpu = try ColourShaderProbe()
        let blue = try gpu.sample(input: .zero, base: SIMD4(0, 0, 0.2, 0.5), glow: SIMD4(0, 0, 0.1, 0.25)).bloom
        #expect(blue.x == 0 && blue.y == 0 && blue.z > 0.2 && abs(blue.w - 0.75) < 0.001)
        let masked = try gpu.sample(input: blue).mask
        #expect(masked.x == 0 && masked.y == 0 && masked.z > 0 && masked.w == blue.w)
        let mono = try gpu.sample(input: .zero, base: .zero, glow: SIMD4(0, 0, 0.1, 0.25), preserve: false).bloom
        #expect(mono.x > 0 && mono.y > 0 && mono.z == 0)
        #expect(try gpu.sample(input: .zero).bloom == .zero)
        let opaque = try gpu.sample(input: .zero, base: SIMD4(0.2, 0.4, 0.6, 1), glow: SIMD4(0.1, 0.2, 0.3, 1)).bloom
        #expect(opaque.w == 1 && abs(opaque.y / opaque.x - 2) < 0.01 && abs(opaque.z / opaque.x - 3) < 0.01)
        #expect([opaque.x, opaque.y, opaque.z, opaque.w].allSatisfy { $0.isFinite })
    }

    private func close(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Bool {
        (0..<4).allSatisfy { abs(a[$0] - b[$0]) < 0.002 }
    }
    private func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        (0..<3).allSatisfy { abs(a[$0] - b[$0]) < 0.002 }
    }
}

@MainActor private final class PaletteProbeView: SwiftTerm.TerminalView {
    var replies: [UInt8] = []
    override func send(source: Terminal, data: ArraySlice<UInt8>) { replies += data }
}

/// Execute production Metal helpers; only the compute entry point is a test
/// adapter. No CPU copy of the shader's colour-conversion formulas is used.
@MainActor private final class ColourShaderProbe {
    let device: MTLDevice
    let pipeline: MTLComputePipelineState
    let queue: MTLCommandQueue
    init() throws {
        device = try #require(MTLCreateSystemDefaultDevice())
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Drum/CRT/CRT.metal")
        let source = try String(contentsOf: url, encoding: .utf8)
        let helpers = try #require(source.components(separatedBy: "// Two rings").first)
        let mask = "// Monochrome tube:" + (try #require(source.components(separatedBy: "// Monochrome tube:").last))
            .components(separatedBy: "// Flyback line")[0]
        let production = (helpers + "\n" + mask)
            .replacingOccurrences(of: "#include <SwiftUI/SwiftUI.h>", with: "")
            .replacingOccurrences(of: "[[stitchable]]", with: "")
        let library = try device.makeLibrary(source: production + """
        kernel void colourProbe(device float4* input [[buffer(0)]], device float4* output [[buffer(1)]],
                                constant float* p [[buffer(2)]]) {
            half4 tint = half4(1, 0.5, 0, 1);
            output[0] = float4(crtMask(float2(p[7], p[8]), half4(input[0]), float4(0, 0, 100, 100),
                                     1, p[1], p[2], p[3], p[4], tint, p[0]));
            output[1] = float4(bloomOutput(half4(input[1]), half4(input[2]), p[5], tint, p[0]));
        }
        """, options: nil)
        pipeline = try device.makeComputePipelineState(function: try #require(library.makeFunction(name: "colourProbe")))
        queue = try #require(device.makeCommandQueue())
    }
    func sample(input: SIMD4<Float>, base: SIMD4<Float> = .zero, glow: SIMD4<Float> = .zero,
                preserve: Bool = true, position: SIMD2<Float> = SIMD2(50.5, 50.5),
                scanlines: Float = 0, grille: Float = 0, vignette: Float = 0, brightness: Float = 1)
        throws -> (mask: SIMD4<Float>, bloom: SIMD4<Float>) {
        let inputs = [input, base, glow]
        let buffer = try #require(inputs.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        })
        let output = try #require(device.makeBuffer(length: 2 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared))
        let parameters: [Float] = [preserve ? 1 : 0, scanlines, grille, vignette, brightness, 1, 0, position.x, position.y]
        let command = try #require(queue.makeCommandBuffer())
        let encoder = try #require(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.setBuffer(output, offset: 0, index: 1)
        parameters.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 2) }
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        try #require(command.status == .completed)
        let values = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: 2)
        return (values[0], values[1])
    }
}
