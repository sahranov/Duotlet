import Foundation
import Metal

@main struct RenderBenchmark {
    static func main() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let library = try device.makeLibrary(source: DepthShaders.source, options: nil)
        let blur = try DepthBlur(device: device, library: library)
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "depthVertex")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "depthFragment")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let projection = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        func texture(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .renderTarget]
            return device.makeTexture(descriptor: descriptor)!
        }
        let source = texture(width: 3504, height: 2444, format: .bgra8Unorm_srgb)
        let output = texture(width: 3024, height: 1964, format: .bgra8Unorm)
        // Initialize a detailed fixture. An uninitialized/black private texture
        // can hide memory bandwidth and cache costs of real screen contents.
        let fixture = device.makeBuffer(length: source.width * source.height * 4, options: .storageModeShared)!
        let pixels = fixture.contents().bindMemory(to: UInt32.self, capacity: source.width * source.height)
        for y in 0..<source.height {
            for x in 0..<source.width {
                let detail = UInt32(truncatingIfNeeded: x &* 1664525 &+ y &* 1013904223)
                pixels[y * source.width + x] = 0xff000000 | (detail & 0x00ffffff)
            }
        }
        let upload = queue.makeCommandBuffer()!
        let copy = upload.makeBlitCommandEncoder()!
        copy.copy(from: fixture, sourceOffset: 0, sourceBytesPerRow: source.width * 4,
            sourceBytesPerImage: fixture.length,
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: source, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        copy.endEncoding()
        upload.commit()
        upload.waitUntilCompleted()
        var uniforms = DepthUniforms(column0: SIMD4(1, 0, 0, 0), column1: SIMD4(0, 1, 0, 0),
            column2: SIMD4(0, 0, 1, 0), screenAndOrigin: SIMD4(1512, 982, -120, -120),
            paddedAndBlur: SIMD4(1752, 1222, 137.8, 1), shape: SIMD4(0, 0.1542, 2, 0), light: SIMD4(0.2, 1, 0.25, 1))
        var times: [Double] = []
        for frame in 0..<40 {
            let commands = queue.makeCommandBuffer()!
            uniforms.paddedAndBlur.w = frame % 2 == 0 ? 0.35 : 1
            let picture = blur.encode(source: source, uniforms: uniforms, into: commands)!
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            let encoder = commands.makeRenderCommandEncoder(descriptor: pass)!
            encoder.setRenderPipelineState(projection)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DepthUniforms>.stride, index: 0)
            encoder.setFragmentTexture(picture, index: 0)
            encoder.setFragmentTexture(source, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            guard commands.status == .completed else { fatalError("GPU failure: \(String(describing: commands.error))") }
            if frame >= 8 { times.append((commands.gpuEndTime - commands.gpuStartTime) * 1000) }
        }
        times.sort()
        let average = times.reduce(0, +) / Double(times.count)
        let p95 = times[Int(Double(times.count - 1) * 0.95)]
        print("GPU: \(device.name)")
        print(String(format: "Production blur + projection: mean %.2f ms, p95 %.2f ms, max %.2f ms", average, p95, times.last!))
        print(p95 <= 8 ? "PASS: isolated GPU work is below 8 ms; verify live presentation separately" : "FAIL: isolated GPU work exceeds 8 ms")
        if p95 > 8 { exit(1) }
    }
}
