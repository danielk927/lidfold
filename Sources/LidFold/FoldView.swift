import AppKit
import CoreImage
import QuartzCore

/// Renders the captured desktop as a hinged pair of panels.
///
/// The frame is split at the horizontal midline. The bottom panel stays put;
/// the top panel rotates backwards about the crease, so the two behave like
/// the halves of a folding screen. Perspective comes from a negative m34 on
/// the container's sublayerTransform — applying it per-panel instead makes the
/// halves converge on different vanishing points and the crease visibly tears.
final class FoldView: NSView {

    /// Maximum rotation of the top panel, in radians, at full fold.
    private static let maxFoldRadians: CGFloat = .pi / 2.2
    /// Eye distance for the perspective transform. Smaller = stronger.
    private static let eyeDistance: CGFloat = 1400
    private static let maxBlurRadius: CGFloat = 22
    private static let maxShadowOpacity: Float = 0.85

    private let container = CALayer()
    private let topPanel = CALayer()
    private let bottomPanel = CALayer()
    private let creaseShade = CAGradientLayer()

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var progress: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setUpLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setUpLayers()
    }

    override var isFlipped: Bool { true }

    private func setUpLayers() {
        guard let root = layer else { return }
        root.backgroundColor = NSColor.clear.cgColor

        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / Self.eyeDistance
        container.sublayerTransform = perspective

        for panel in [bottomPanel, topPanel] {
            panel.contentsGravity = .resize
            panel.masksToBounds = true
            panel.isDoubleSided = false
            panel.shadowColor = NSColor.black.cgColor
            panel.shadowOffset = .zero
            panel.shadowRadius = 40
            panel.shadowOpacity = 0
            container.addSublayer(panel)
        }

        // The top panel pivots about its own bottom edge, which is the crease.
        topPanel.anchorPoint = CGPoint(x: 0.5, y: 0)

        // A soft darkening along the crease sells the concave fold.
        creaseShade.colors = [
            NSColor.black.withAlphaComponent(0.0).cgColor,
            NSColor.black.withAlphaComponent(0.55).cgColor,
        ]
        creaseShade.startPoint = CGPoint(x: 0.5, y: 0.0)
        creaseShade.endPoint = CGPoint(x: 0.5, y: 1.0)
        creaseShade.opacity = 0
        topPanel.addSublayer(creaseShade)

        root.addSublayer(container)
    }

    override func layout() {
        super.layout()
        layOutPanels()
    }

    private func layOutPanels() {
        // Implicit animations fight the 60Hz sensor updates; every geometry
        // change here must be immediate.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        container.frame = bounds
        let halfHeight = bounds.height / 2

        bottomPanel.frame = CGRect(x: 0, y: halfHeight, width: bounds.width, height: halfHeight)
        // anchorPoint (0.5, 0) means position is the midpoint of the panel's
        // bottom edge, which sits on the crease.
        topPanel.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: halfHeight)
        topPanel.position = CGPoint(x: bounds.midX, y: halfHeight)
        creaseShade.frame = topPanel.bounds

        applyFold()
    }

    /// Feeds a newly captured frame into the two panels.
    func update(with pixelBuffer: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let full = ciContext.createCGImage(image, from: image.extent) else { return }

        let w = full.width
        let h = full.height
        guard let topHalf = full.cropping(to: CGRect(x: 0, y: 0, width: w, height: h / 2)),
              let bottomHalf = full.cropping(to: CGRect(x: 0, y: h / 2, width: w, height: h - h / 2))
        else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topPanel.contents = topHalf
        bottomPanel.contents = bottomHalf
        CATransaction.commit()
    }

    func setProgress(_ newValue: Double) {
        progress = min(max(newValue, 0), 1)
        applyFold()
    }

    private func applyFold() {
        let settings = FoldSettings.shared.effective
        let p = CGFloat(progress)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Rotate the top panel back about the crease (the X axis).
        let angle = Self.maxFoldRadians * p * CGFloat(settings.perspective)
        topPanel.transform = CATransform3DMakeRotation(-angle, 1, 0, 0)

        let blurRadius = Self.maxBlurRadius * p * CGFloat(settings.blur)
        if blurRadius > 0.5, let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(blurRadius, forKey: kCIInputRadiusKey)
            topPanel.filters = [blur]
            bottomPanel.filters = [blur]
        } else {
            topPanel.filters = nil
            bottomPanel.filters = nil
        }

        let shadow = Self.maxShadowOpacity * Float(p) * Float(settings.shadow)
        topPanel.shadowOpacity = shadow
        bottomPanel.shadowOpacity = shadow * 0.5

        creaseShade.opacity = Float(p) * 0.9
    }
}
