import AppKit
import Metal
import Testing
@testable import Drum

@Suite(.serialized) @MainActor
struct TerminalPointerMapTests {
    @Test func pointerCoordinatesMatchTheActualMetalShaderDuringWobble() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Drum/CRT/CRT.metal")
        let shader = try String(contentsOf: sourceURL, encoding: .utf8)
            .components(separatedBy: "// Two rings")[0]
            .replacingOccurrences(of: "#include <SwiftUI/SwiftUI.h>", with: "")
            .replacingOccurrences(of: "[[stitchable]]", with: "")
        let library = try device.makeLibrary(source: shader + """
        kernel void sample(device float2* points [[buffer(0)]], device float2* result [[buffer(1)]],
                           constant float* p [[buffer(2)]], uint i [[thread_position_in_grid]]) {
            result[i] = crtBarrel(points[i], float4(0, 0, p[0], p[1]), p[2], p[3], p[4], p[5]);
        }
        """, options: nil)
        let function = try #require(library.makeFunction(name: "sample"))
        let pipeline = try device.makeComputePipelineState(function: function)
        let queue = try #require(device.makeCommandQueue())
        var maximumError: Float = 0
        for size in [CGSize(width: 640, height: 360), CGSize(width: 1280, height: 400),
                     CGSize(width: 2560, height: 720)] {
            let terminalSize = CGSize(width: size.width - 56, height: size.height - 40)
            let points = (0..<Int(size.height)).flatMap { row in
                [CGFloat(0.5), size.width * 0.1, size.width * 0.5, size.width - 0.5].map {
                    SIMD2<Float>(Float($0), Float(row) + 0.5)
                }
            }
            let byteCount = points.count * MemoryLayout<SIMD2<Float>>.stride
            let input = try #require(points.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: byteCount, options: .storageModeShared)
            })
            let output = try #require(device.makeBuffer(length: byteCount, options: .storageModeShared))
            for time in [TimeInterval(0), 0.1, 81.25, 368.9] {
                var settings = CRTSettings()
                settings.barrelX = 0.15; settings.barrelY = 0.15; settings.wobble = 0.01
                let map = TerminalPointerMap(settings: settings, time: time)
                let parameters: [Float] = [Float(size.width), Float(size.height), 0.15, 0.15, 0.01,
                                          Float(time.truncatingRemainder(dividingBy: CRTEffect.timePeriod))]
                let command = try #require(queue.makeCommandBuffer())
                let encoder = try #require(command.makeComputeCommandEncoder())
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(input, offset: 0, index: 0)
                encoder.setBuffer(output, offset: 0, index: 1)
                parameters.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 2) }
                encoder.dispatchThreads(MTLSize(width: points.count, height: 1, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: min(64, pipeline.maxTotalThreadsPerThreadgroup),
                                                                     height: 1, depth: 1))
                encoder.endEncoding()
                command.commit(); command.waitUntilCompleted()
                #expect(command.status == .completed)
                let gpu = output.contents().bindMemory(to: SIMD2<Float>.self, capacity: points.count)
                for (index, point) in points.enumerated() {
                    let local = CGPoint(x: CGFloat(point.x) - 28,
                                        y: terminalSize.height - (CGFloat(point.y) - 22))
                    let cpu = map.sourcePoint(local, terminalSize: terminalSize)
                    let xError = abs(Float(cpu.x + 28) - gpu[index].x)
                    let yError = abs(Float(terminalSize.height - cpu.y + 22) - gpu[index].y)
                    maximumError = max(maximumError, xError, yError)
                }
            }
        }
        #expect(maximumError < 0.002, "CPU and GPU mapping must agree within a fraction of one device pixel")
        let evidence = try JSONSerialization.data(withJSONObject: ["maximumErrorPoints": maximumError,
                                                                   "maximumWobble": 0.01, "maximumCurvature": 0.15])
        try evidence.write(to: URL(fileURLWithPath: "/tmp/drum-pointer-map-evidence.json"), options: .atomic)
    }
}
