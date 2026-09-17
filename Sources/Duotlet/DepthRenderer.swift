import AppKit
import Metal
import QuartzCore
import simd

/// Draws the picture with Metal.
///
/// A full-resolution original plus a separately blurred image are projected
/// and faded in one GPU frame.
@MainActor
final class DepthRenderer {

    /// Black margin around the picture, in points. Stays above the largest
    /// blur radius, so the blur reaches real black on every side.
    nonisolated private static let paddingInPoints: CGFloat = 120

    private typealias Uniforms = DepthUniforms

    /// One held picture, built off the main thread and adopted on it.
    struct PreparedPicture {
        let texture: MTLTexture
        let colourSpace: CGColorSpace
        let paddedOrigin: CGPoint
        let paddedSize: CGSize
        let maxLevel: Float
        let pixelScale: CGFloat
        let screenSize: CGSize
    }

    /// Where the next frame goes.
    ///
    /// A layer belongs to one view at a time, so every overlay window needs
    /// its own.
    private(set) var layer = CAMetalLayer()

    nonisolated private let device: MTLDevice
    nonisolated private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let blurProcessor: DepthBlur
    private var profile: AnimationProfile?
    private var texture: MTLTexture?
    private var screenSize: CGSize = .zero
    private var pixelScale: CGFloat = 2
    private var paddedOrigin: CGPoint = .zero
    private var paddedSize: CGSize = .zero
    private var maxLevel: Float = 0

    /// The picture a live stream writes into. `makePicture` builds its own
    /// texture instead, so only one of the two is in use at a time.
    private var liveTexture: MTLTexture?
    private var liveSize: CGSize = .zero
    private var liveScale: CGFloat = 0
    private var isLiveSource = false
    /// The newest live frame, waiting for the next drawn frame to take it.
    private var pendingFrame: CapturedFrame?
    /// A held picture to start from, waiting for the same moment. A live
    /// frame that arrives first wins, since it is the newer of the two.
    private var pendingSeed: (buffer: MTLBuffer, width: Int, height: Int)?

    var isReady: Bool { texture != nil }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue

        do {
            let library = try device.makeLibrary(source: DepthShaders.source, options: nil)
            blurProcessor = try DepthBlur(device: device, library: library)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "depthVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "depthFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            Diagnostics.geometry.error("metal pipeline failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        configure(layer)
    }

    /// A fresh layer for a new overlay window. Later frames go to this one.
    func makeLayer() -> CAMetalLayer {
        profile = AnimationProfile.enabled ? AnimationProfile() : nil
        let fresh = CAMetalLayer()
        configure(fresh)
        fresh.colorspace = layer.colorspace
        fresh.drawableSize = layer.drawableSize
        layer = fresh
        return fresh
    }

    private func configure(_ target: CAMetalLayer) {
        target.device = device
        target.pixelFormat = .bgra8Unorm
        target.maximumDrawableCount = 3
        target.framebufferOnly = true
        // An opaque layer covering the screen makes the window server mark
        // every window behind it as hidden, and apps stop drawing. Opacity
        // is part of each rendered frame, including the final fade to zero.
        target.isOpaque = false
        // Display-link callbacks alone do not synchronize presentation. With
        // immediate presentation, GPU completion jitter becomes visible during
        // the fade. Three surfaces let rendering overlap the synchronized
        // presentation without waiting for the displayed surface on the CPU.
        target.displaySyncEnabled = true
        target.needsDisplayOnBoundsChange = true
    }

    /// Puts the picture on a black margin and uploads it at full resolution.
    /// Call this off the main thread.
    nonisolated func makePicture(image: CGImage, screenSize: CGSize, pixelScale: CGFloat) -> PreparedPicture? {
        let started = CFAbsoluteTimeGetCurrent()
        let padding = Self.paddingInPoints
        let paddedSize = CGSize(
            width: screenSize.width + 2 * padding,
            height: screenSize.height + 2 * padding
        )
        let width = Int((paddedSize.width * pixelScale).rounded())
        let height = Int((paddedSize.height * pixelScale).rounded())
        guard width > 0, height > 0 else { return nil }
        let byteCount = width * height * 4

        guard let staging = device.makeBuffer(length: byteCount, options: .storageModeShared) else { return nil }

        let colourSpace: CGColorSpace
        if let space = image.colorSpace, space.model == .rgb {
            colourSpace = space
        } else {
            colourSpace = CGColorSpaceCreateDeviceRGB()
        }
        guard let context = CGContext(
            data: staging.contents(),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colourSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        let contextReady = CFAbsoluteTimeGetCurrent()

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let inset = padding * pixelScale
        context.draw(image, in: CGRect(
            x: inset,
            y: inset,
            width: CGFloat(width) - 2 * inset,
            height: CGFloat(height) - 2 * inset
        ))
        let drawn = CFAbsoluteTimeGetCurrent()

        let levels = 1
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(
            from: staging,
            sourceOffset: 0,
            sourceBytesPerRow: width * 4,
            sourceBytesPerImage: byteCount,
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()

        commands.commit()
        commands.waitUntilCompleted()
        let finished = CFAbsoluteTimeGetCurrent()

        Diagnostics.geometry.notice(
            """
            metal texture \(width)x\(height) px, \(levels) levels: \
            context \((contextReady - started) * 1000, format: .fixed(precision: 1)) ms, \
            draw \((drawn - contextReady) * 1000, format: .fixed(precision: 1)) ms, \
            gpu \((finished - drawn) * 1000, format: .fixed(precision: 1)) ms
            """
        )
        return PreparedPicture(
            texture: texture,
            colourSpace: colourSpace,
            paddedOrigin: CGPoint(x: -padding, y: -padding),
            paddedSize: paddedSize,
            maxLevel: Float(levels - 1),
            pixelScale: pixelScale,
            screenSize: screenSize
        )
    }

    // MARK: - Live source

    /// Prepares the picture for a live stream. The margin is filled with black
    /// once; every frame after that only overwrites the interior. Nothing is
    /// drawn until the first frame lands.
    @discardableResult
    func beginLive(screenSize: CGSize, pixelScale: CGFloat) -> Bool {
        let padding = Self.paddingInPoints
        let padded = CGSize(
            width: screenSize.width + 2 * padding,
            height: screenSize.height + 2 * padding
        )
        let width = Int((padded.width * pixelScale).rounded())
        let height = Int((padded.height * pixelScale).rounded())
        guard width > 0, height > 0 else { return false }

        if liveTexture == nil || liveSize != padded || liveScale != pixelScale {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb,
                width: width,
                height: height,
                mipmapped: false
            )
            // `renderTarget` is only there for the one clear that blacks the
            // margin.
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private
            guard let fresh = device.makeTexture(descriptor: descriptor) else { return false }
            clearToBlack(fresh)
            liveTexture = fresh
            liveSize = padded
            liveScale = pixelScale
        }

        texture = nil
        isLiveSource = true
        self.screenSize = screenSize
        self.pixelScale = pixelScale
        paddedOrigin = CGPoint(x: -padding, y: -padding)
        paddedSize = padded
        maxLevel = 0
        layer.colorspace = CGColorSpace(name: ScreenStreamer.colourSpaceName)
        layer.drawableSize = CGSize(
            width: screenSize.width * pixelScale,
            height: screenSize.height * pixelScale
        )
        return true
    }

    /// Starts the live picture from one held frame. The stream's first frame
    /// overwrites it.
    @discardableResult
    func seed(image: CGImage) -> Bool {
        guard isLiveSource, liveTexture != nil else { return false }
        let inset = Int((Self.paddingInPoints * pixelScale).rounded())
        let width = Int((screenSize.width * pixelScale).rounded())
        let height = Int((screenSize.height * pixelScale).rounded())
        guard width > 0, height > 0, inset >= 0 else { return false }
        let bytesPerRow = width * 4
        guard let staging = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              // The stream's own space, so the handover does not shift colour.
              let space = CGColorSpace(name: ScreenStreamer.colourSpaceName),
              let context = CGContext(
                data: staging.contents(),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        pendingSeed = (staging, width, height)
        texture = liveTexture
        return true
    }

    func absorb(_ frame: CapturedFrame) {
        guard isLiveSource, liveTexture != nil else { return }
        pendingFrame = frame
        pendingSeed = nil
        // The texture object is the one the next pass reads, and the copy into
        // it is encoded ahead of that pass.
        texture = liveTexture
    }

    /// Copies the newest frame before encoding blur and projection.
    private func absorbPending(into commands: MTLCommandBuffer) {
        guard let target = liveTexture, pendingFrame != nil || pendingSeed != nil else { return }
        let inset = Int((Self.paddingInPoints * pixelScale).rounded())
        guard let blit = commands.makeBlitCommandEncoder() else { return }
        if let frame = pendingFrame {
            let width = min(frame.texture.width, target.width - 2 * inset)
            let height = min(frame.texture.height, target.height - 2 * inset)
            guard width > 0, height > 0 else { blit.endEncoding(); return }
            blit.copy(
                from: frame.texture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: target,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: inset, y: inset, z: 0)
            )
            commands.addCompletedHandler { [frame] _ in
                withExtendedLifetime(frame) {}
            }
        } else if let seed = pendingSeed {
            let width = min(seed.width, target.width - 2 * inset)
            let height = min(seed.height, target.height - 2 * inset)
            guard width > 0, height > 0 else { blit.endEncoding(); return }
            blit.copy(
                from: seed.buffer,
                sourceOffset: 0,
                sourceBytesPerRow: seed.width * 4,
                sourceBytesPerImage: seed.width * 4 * seed.height,
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: target,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: inset, y: inset, z: 0)
            )
        }
        pendingFrame = nil
        pendingSeed = nil
        blit.endEncoding()
        liveTexture = target
        texture = target
    }

    /// Frees the live picture.
    func discardLive() {
        pendingFrame = nil
        pendingSeed = nil
        if isLiveSource { texture = nil }
        isLiveSource = false
        liveTexture = nil
        liveSize = .zero
        liveScale = 0
    }

    private func clearToBlack(_ target: MTLTexture) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
    }

    // MARK: - Still source

    func adopt(_ picture: PreparedPicture) {
        isLiveSource = false
        texture = picture.texture
        // Without a tag the window server treats the drawable as sRGB and
        // converts it to the display space.
        layer.colorspace = picture.colourSpace
        paddedOrigin = picture.paddedOrigin
        paddedSize = picture.paddedSize
        maxLevel = picture.maxLevel
        pixelScale = picture.pixelScale
        screenSize = picture.screenSize
        layer.drawableSize = CGSize(
            width: picture.screenSize.width * picture.pixelScale,
            height: picture.screenSize.height * picture.pixelScale
        )
    }

    func release() {
        profile?.reportAfterCompletion()
        profile = nil
        texture = nil
        blurProcessor.release()
        // The old window can retain its layer until its fade ends. The
        // renderer must not keep that full-screen drawable pool alive idle.
        layer = CAMetalLayer()
        configure(layer)
    }

    /// - Parameter corners: the picture corners projected onto the screen, in
    ///   points, listed bottom-left, bottom-right, top-right, top-left.
    func render(
        corners: [CGPoint],
        blurStrength: Double,
        dimStrength: Double,
        hingeFloor: Double,
        dimHingeFloor: Double,
        dimReach: Double,
        maxBlurRadius: Double,
        maxDim: Double,
        opacity: Double = 1
    ) {
        guard let commands = queue.makeCommandBuffer() else { return }
        absorbPending(into: commands)
        guard let texture, screenSize.width > 0, screenSize.height > 0 else {
            commands.commit()
            return
        }
        let drawableStarted = profile == nil ? 0 : CACurrentMediaTime()
        let next = layer.nextDrawable()
        if profile != nil {
            let wait = CACurrentMediaTime() - drawableStarted
            if wait > 0.025 {
                Diagnostics.geometry.notice("profile drawable wait: \(wait * 1000, format: .fixed(precision: 2)) ms")
            }
        }
        guard let drawable = next else {
            commands.commit()
            return
        }

        let forward = Homography.matrix(
            width: Double(screenSize.width),
            height: Double(screenSize.height),
            to: corners.map { SIMD2(Double($0.x), Double($0.y)) }
        )
        let inverse = forward.inverse

        func column(_ index: Int) -> SIMD4<Float> {
            let c = inverse[index]
            return SIMD4(Float(c.x), Float(c.y), Float(c.z), 0)
        }
        var uniforms = Uniforms(
            column0: column(0),
            column1: column(1),
            column2: column(2),
            screenAndOrigin: SIMD4(
                Float(screenSize.width), Float(screenSize.height),
                Float(paddedOrigin.x), Float(paddedOrigin.y)
            ),
            paddedAndBlur: SIMD4(
                Float(paddedSize.width), Float(paddedSize.height),
                Float(maxBlurRadius * Double(pixelScale)), Float(blurStrength)
            ),
            shape: SIMD4(Float(hingeFloor), Float(maxDim), Float(pixelScale), maxLevel),
            light: SIMD4(Float(dimHingeFloor), Float(dimStrength), Float(dimReach), Float(opacity))
        )

        guard let renderedPicture = blurProcessor.encode(source: texture, uniforms: uniforms, into: commands)
        else { commands.commit(); return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            commands.commit()
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(renderedPicture, index: 0)
        encoder.setFragmentTexture(texture, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let profile {
            drawable.addPresentedHandler { profile.presented(at: $0.presentedTime) }
            commands.addCompletedHandler { profile.completed(in: $0.gpuEndTime - $0.gpuStartTime) }
        }
        commands.present(drawable)
        commands.commit()
    }
}
