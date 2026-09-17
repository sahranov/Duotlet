import Metal

/// Keep the original screen sharp. Only the blurred image uses half-sized
/// working buffers; the fragment shader smoothly selects the original for
/// blur radii too small to justify resampling.
final class DepthBlur {
    private let device: MTLDevice
    private let downsample: MTLComputePipelineState
    private let blur: MTLComputePipelineState
    private var horizontal: MTLTexture?
    private var vertical: MTLTexture?

    init(device: MTLDevice, library: MTLLibrary) throws {
        self.device = device
        downsample = try device.makeComputePipelineState(function: library.makeFunction(name: "reduceForBlur")!)
        blur = try device.makeComputePipelineState(function: library.makeFunction(name: "denseBlur")!)
    }

    func release() {
        horizontal = nil
        vertical = nil
    }

    func encode(source: MTLTexture, uniforms: DepthUniforms, into commands: MTLCommandBuffer) -> MTLTexture? {
        // depthFragment uses only the native image at sigma <= 0.4. Six
        // full-buffer passes here would contribute exactly zero to the frame.
        let maximumSigma = 0.5 * uniforms.paddedAndBlur.z * uniforms.paddedAndBlur.w
        guard maximumSigma > 0.4 else { return source }
        let width = (source.width + 1) / 2
        let height = (source.height + 1) / 2
        if vertical?.width != width || vertical?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .shaderWrite]
            horizontal = device.makeTexture(descriptor: descriptor)
            vertical = device.makeTexture(descriptor: descriptor)
        }
        guard let horizontal, let vertical,
              let reduction = commands.makeComputeCommandEncoder() else { return nil }
        reduction.setComputePipelineState(downsample)
        reduction.setTexture(source, index: 0)
        reduction.setTexture(vertical, index: 1)
        reduction.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                  threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        reduction.endEncoding()

        var working = uniforms
        working.paddedAndBlur.z *= 0.5
        for stage in 0..<6 {
            var axis = UInt32(stage % 2)
            var segmentLength: UInt32 = 32
            guard let encoder = commands.makeComputeCommandEncoder() else { return nil }
            encoder.setComputePipelineState(blur)
            encoder.setTexture(axis == 0 ? vertical : horizontal, index: 0)
            encoder.setTexture(axis == 0 ? horizontal : vertical, index: 1)
            encoder.setBytes(&working, length: MemoryLayout<DepthUniforms>.stride, index: 0)
            encoder.setBytes(&axis, length: MemoryLayout<UInt32>.stride, index: 1)
            encoder.setBytes(&segmentLength, length: MemoryLayout<UInt32>.stride, index: 2)
            let lines = axis == 0 ? height : width
            let length = axis == 0 ? width : height
            let segments = (length + Int(segmentLength) - 1) / Int(segmentLength)
            encoder.dispatchThreads(MTLSize(width: lines * segments, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
            encoder.endEncoding()
        }
        return vertical
    }
}
