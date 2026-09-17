import Foundation
import Metal

/// Runs the production GPU path, including the sharp image and premultiplied fade.
@main
struct BlurRegression {
    static func main() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let library = try device.makeLibrary(source: DepthShaders.source, options: nil)
        let blur = try DepthBlur(device: device, library: library)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "depthVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "depthFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let size = 256
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
            width: size, height: size, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .renderTarget]
        let source = device.makeTexture(descriptor: textureDescriptor)!
        let output = device.makeTexture(descriptor: textureDescriptor)!

        func render(_ pixels: [Float], radius: Float, opacity: Float = 1) throws -> [Float] {
            pixels.withUnsafeBytes {
                source.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: size * 16)
            }
            var uniforms = DepthUniforms(
                column0: SIMD4(1, 0, 0, 0), column1: SIMD4(0, 1, 0, 0), column2: SIMD4(0, 0, 1, 0),
                screenAndOrigin: SIMD4(Float(size), Float(size), 0, 0),
                paddedAndBlur: SIMD4(Float(size), Float(size), radius, 1),
                shape: SIMD4(1, 0, 1, 0), light: SIMD4(0, 0, 1, opacity))
            let commands = queue.makeCommandBuffer()!
            let picture = blur.encode(source: source, uniforms: uniforms, into: commands)!
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            let encoder = commands.makeRenderCommandEncoder(descriptor: pass)!
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DepthUniforms>.stride, index: 0)
            encoder.setFragmentTexture(picture, index: 0)
            encoder.setFragmentTexture(source, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            if let error = commands.error { throw error }
            var result = [Float](repeating: 0, count: pixels.count)
            result.withUnsafeMutableBytes {
                output.getBytes($0.baseAddress!, bytesPerRow: size * 16,
                    from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
            }
            return result
        }

        var failures = 0
        func check(_ pass: Bool, _ description: String) {
            print("\(pass ? "PASS" : "FAIL"): \(description)")
            if !pass { failures += 1 }
        }
        var neutral = DepthUniforms(
            column0: SIMD4(1, 0, 0, 0), column1: SIMD4(0, 1, 0, 0), column2: SIMD4(0, 0, 1, 0),
            screenAndOrigin: SIMD4(Float(size), Float(size), 0, 0),
            paddedAndBlur: SIMD4(Float(size), Float(size), 0.8, 1),
            shape: SIMD4(1, 0, 1, 0), light: SIMD4(0, 0, 1, 1))
        let neutralCommands = queue.makeCommandBuffer()!
        check(blur.encode(source: source, uniforms: neutral, into: neutralCommands) === source,
              "imperceptible blur returns original without six compute passes")
        neutral.paddedAndBlur.z = 0.81
        check(blur.encode(source: source, uniforms: neutral, into: neutralCommands) !== source,
              "blur still runs as soon as the fragment shader begins showing it")
        neutralCommands.commit()
        neutralCommands.waitUntilCompleted()
        for ring in [false, true] {
            var pixels = [Float](repeating: 0, count: size * size * 4)
            for y in 0..<size {
                for x in 0..<size {
                    let index = (y * size + x) * 4
                    let distance = hypot(Double(x - size / 2), Double(y - size / 2))
                    let lit = ring ? abs(distance - 48) <= 1.5 : abs(x - size / 2) <= 1
                    for c in 0..<3 { pixels[index + c] = lit ? 1 : 0 }
                    pixels[index + 3] = 1
                }
            }
            for radius: Float in [0, 8, 32, 64] {
                let result = try render(pixels, radius: radius)
                let line = (0..<size).map { result[(size / 2 * size + $0) * 4] }
                let rises = ((size / 2 + (ring ? 50 : 2))..<(size - 1))
                    .filter { line[$0 + 1] - line[$0] > 0.0001 }.count
                let error = radius == 0 ? zip(result, pixels).map { abs($0 - $1) }.max()! : 0
                check(rises == 0 && error < 0.0001,
                    "\(ring ? "ring" : "line") radius=\(radius), secondary rises=\(rises), sharp error=\(error)")
            }
        }
        // Fine colour detail must remain full resolution as blur reaches zero.
        let palette: [Float] = [0.002, 0.02, 0.18, 0.6, 1]
        let colour = (0..<(size * size * 4)).map { i -> Float in
            i % 4 == 3 ? 1 : palette[(i / 4 + i % 4) % palette.count]
        }
        func encode(_ value: Float) -> Float {
            value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
        }
        for opacity: Float in [1, 0.5, 0.01, 0.001, 0] {
            let result = try render(colour, radius: 0, opacity: opacity)
            let error = result.indices.map {
                abs(result[$0] - ($0 % 4 == 3 ? opacity : encode(colour[$0]) * opacity))
            }.max()!
            check(error < 0.0001, "native colour + premultiplied fade, opacity=\(opacity), error=\(error)")
        }
        // Sweep every intermediate radius: changing blur levels must not make
        // fine detail disappear again while the screen is sharpening.
        var line = [Float](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                for c in 0..<3 { line[(y * size + x) * 4 + c] = abs(x - size / 2) <= 1 ? 1 : 0 }
                line[(y * size + x) * 4 + 3] = 1
            }
        }
        var previousPeak: Float = 0
        var regressions = 0
        for step in stride(from: 128, through: 0, by: -1) {
            let result = try render(line, radius: Float(step) * 0.5)
            let peak = result[(size / 2 * size + size / 2) * 4]
            if peak < previousPeak - 0.0001 { regressions += 1 }
            previousPeak = peak
        }
        check(regressions == 0, "continuous sharpening through all blur radii, reversals=\(regressions)")
        if failures > 0 { exit(1) }
    }
}
