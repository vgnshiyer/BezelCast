import SwiftUI
import AppKit
import AVFoundation

struct LayeredCapturePreview: NSViewRepresentable {
    let session: AVCaptureSession
    let profile: DeviceProfile
    let customFrame: NSImage?

    func makeNSView(context: Context) -> LayeredPreviewView {
        let view = LayeredPreviewView()
        view.configure(session: session, profile: profile, customFrame: customFrame)
        return view
    }

    func updateNSView(_ nsView: LayeredPreviewView, context: Context) {
        nsView.configure(session: session, profile: profile, customFrame: customFrame)
    }

    static func dismantleNSView(_ nsView: LayeredPreviewView, coordinator: ()) {
        nsView.detachSession()
    }
}

final class LayeredPreviewView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let bezelLayer = CALayer()

    private var profile: DeviceProfile = DeviceProfile.catalog.first!
    private var hasCustomFrame = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.backgroundColor = NSColor.clear.cgColor
        rootLayer.masksToBounds = false
        rootLayer.shadowColor = NSColor.black.cgColor
        rootLayer.shadowOpacity = 0.25
        rootLayer.shadowRadius = 24
        rootLayer.shadowOffset = CGSize(width: 0, height: -8)
        layer = rootLayer

        previewLayer.videoGravity = .resizeAspect
        previewLayer.masksToBounds = true
        previewLayer.backgroundColor = NSColor.clear.cgColor

        bezelLayer.contentsGravity = .resize
        bezelLayer.masksToBounds = false
        bezelLayer.isOpaque = false

        rootLayer.addSublayer(previewLayer)
        rootLayer.addSublayer(bezelLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(session: AVCaptureSession, profile: DeviceProfile, customFrame: NSImage?) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }

        self.profile = profile
        hasCustomFrame = customFrame != nil

        if let customFrame,
           let cgImage = customFrame.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            bezelLayer.contents = cgImage
            bezelLayer.isHidden = false
        } else {
            bezelLayer.contents = nil
            bezelLayer.isHidden = true
        }

        updateBackingScale()
        needsLayout = true
    }

    func detachSession() {
        previewLayer.session = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackingScale()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        let bounds = CGRect(origin: .zero, size: self.bounds.size)
        guard bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if hasCustomFrame {
            let scaleX = bounds.width / profile.frameSize.width
            let scaleY = bounds.height / profile.frameSize.height
            let screenWidth = profile.screenSize.width * scaleX
            let screenHeight = profile.screenSize.height * scaleY
            let screenX = profile.screenOffset.x * scaleX
            let screenYFromTop = profile.screenOffset.y * scaleY
            let screenY = bounds.height - screenYFromTop - screenHeight

            previewLayer.frame = CGRect(x: screenX, y: screenY,
                                        width: screenWidth, height: screenHeight)
            previewLayer.cornerRadius = profile.screenCornerRadius * min(scaleX, scaleY)
            bezelLayer.frame = bounds

            let outerCorner = previewLayer.cornerRadius + min(screenX, screenYFromTop)
            layer?.shadowPath = CGPath(roundedRect: bounds,
                                       cornerWidth: outerCorner,
                                       cornerHeight: outerCorner,
                                       transform: nil)
        } else {
            let scale = min(bounds.width / profile.screenSize.width,
                            bounds.height / profile.screenSize.height)
            previewLayer.frame = bounds
            previewLayer.cornerRadius = profile.screenCornerRadius * scale
            bezelLayer.frame = bounds
            layer?.shadowPath = CGPath(roundedRect: bounds,
                                       cornerWidth: previewLayer.cornerRadius,
                                       cornerHeight: previewLayer.cornerRadius,
                                       transform: nil)
        }

        CATransaction.commit()
    }

    private func updateBackingScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        previewLayer.contentsScale = scale
        bezelLayer.contentsScale = scale
    }
}
