import MetalKit
import CoreVideo

/// Renders the captured desktop folding back about a hinge along the bottom of
/// the screen.
///
/// The fold is done per-pixel in a fragment shader rather than by transforming
/// layers: for each pixel on screen it works out which part of the captured
/// image would land there once the plane has rotated about the hinge. That
/// keeps the blur on the GPU, where it can read the mip chain, instead of
/// running a `CIGaussianBlur` over two full-screen layers every frame.
final class MetalFoldView: MTKView, MTKViewDelegate {

    /// How far the panel has physically rotated away from vertical, for a given
    /// fold progress.
    ///
    /// Progress is a straight remapping of the lid angle, so it can be run back
    /// the other way to recover the angle and from there the rotation. The
    /// image is counter-rotated by exactly this, which is what pins the desktop
    /// in space instead of turning it with the panel. Nothing here is a free
    /// parameter — invent the angle and the illusion stops holding.
    /// Fraction of the panel's rotation the image counter-rotates by.
    ///
    /// At 1 the desktop is pinned exactly upright and the panel sweeps through
    /// it — geometrically the real thing, and far too strong to look at: by the
    /// time the lid is shut the image has collapsed to under a tenth of its
    /// height. Below 1 the desktop leans with the panel instead of standing
    /// against it, so the illusion is no longer exact, but it still reads as
    /// the screen resisting the fold rather than folding with it.
    static let counterRotation: Float = 0.30

    /// Frosted defocus, and the falloff into the void behind the panel edge.
    private static let blurStrength: Float = 0.755
    private static let darkness: Float = 0.753

    /// Viewing distance in panel heights. Far enough back that the projection
    /// is nearly orthographic, which is most of what keeps the keystone mild.
    static let eyeDistance: Float = 5.5

    static func panelTilt(forProgress progress: Float) -> Float {
        let start = LidAngleMonitor.foldStartAngle
        let end = LidAngleMonitor.foldEndAngle
        let angle = start - Double(progress) * (start - end)
        return Float(max(0, 90 - angle) * .pi / 180)
    }

    private struct Uniforms {
        var texelSize: SIMD2<Float>
        var aspect: Float
        var progress: Float
        var tilt: Float
        var eyeDistance: Float
        var blur: Float
        var darkness: Float
    }

    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?

    /// Zero-copy bridge from the capture pipeline's `CVPixelBuffer`s.
    private var textureCache: CVMetalTextureCache?
    /// Mipmapped copy of the latest frame. The cache hands back textures with
    /// no mip chain, and the blur needs one.
    private var mipTexture: MTLTexture?

    private var progress: Float = 0

    init(frame: CGRect) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { fatalError("Metal is unavailable on this Mac") }
        self.commandQueue = queue

        super.init(frame: frame, device: device)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        // The fold only redraws when a frame arrives or the angle moves, so
        // there is no reason to run a display link while the lid is open.
        isPaused = true
        enableSetNeedsDisplay = true
        delegate = self

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        buildPipeline(device)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func buildPipeline(_ device: MTLDevice) {
        guard let library = try? device.makeLibrary(source: foldShaderSource, options: nil) else {
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

        let sampleDescriptor = MTLSamplerDescriptor()
        sampleDescriptor.minFilter = .linear
        sampleDescriptor.magFilter = .linear
        sampleDescriptor.mipFilter = .linear
        sampleDescriptor.sAddressMode = .clampToEdge
        sampleDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sampleDescriptor)
    }

    /// Feeds a newly captured frame in.
    func update(with pixelBuffer: CVPixelBuffer) {
        guard let device, let cache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var wrapped: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &wrapped
        )
        guard status == kCVReturnSuccess,
              let wrapped, let source = CVMetalTextureGetTexture(wrapped)
        else { return }

        if mipTexture?.width != width || mipTexture?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: true
            )
            descriptor.usage = [.shaderRead, .renderTarget]
            descriptor.storageMode = .private
            mipTexture = device.makeTexture(descriptor: descriptor)
        }
        guard let destination = mipTexture,
              let buffer = commandQueue.makeCommandBuffer(),
              let blit = buffer.makeBlitCommandEncoder()
        else { return }

        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: destination, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.generateMipmaps(for: destination)
        blit.endEncoding()
        buffer.commit()

        needsDisplay = true
    }

    func setProgress(_ newValue: Double) {
        progress = Float(min(max(newValue, 0), 1))
        needsDisplay = true
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline, let sampler, let texture = mipTexture,
              let descriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        var uniforms = Uniforms(
            texelSize: SIMD2(1 / Float(texture.width), 1 / Float(texture.height)),
            aspect: Float(drawableSize.width / max(drawableSize.height, 1)),
            progress: progress,
            tilt: Self.panelTilt(forProgress: progress) * Self.counterRotation,
            eyeDistance: Self.eyeDistance,
            blur: Self.blurStrength,
            darkness: Self.darkness
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        buffer.present(drawable)
        buffer.commit()
    }
}
