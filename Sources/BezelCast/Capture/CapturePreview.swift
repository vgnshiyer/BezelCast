import SwiftUI
import AppKit

struct LayeredCapturePreview: NSViewRepresentable {
    let profile: DeviceProfile
    let customFrame: CustomFrame?
    let previewFrames: PreviewFrameStore

    func makeNSView(context: Context) -> LayeredPreviewView {
        let view = LayeredPreviewView()
        view.configure(profile: profile,
                       customFrame: customFrame,
                       previewFrames: previewFrames)
        return view
    }

    func updateNSView(_ nsView: LayeredPreviewView, context: Context) {
        nsView.configure(profile: profile,
                         customFrame: customFrame,
                         previewFrames: previewFrames)
    }

    static func dismantleNSView(_ nsView: LayeredPreviewView, coordinator: ()) {
        nsView.detachPreview()
    }
}

final class LayeredPreviewView: NSView {
    private let compositedLayer = CALayer()

    private var profile: DeviceProfile = DeviceProfile.catalog.first!
    private var hasCustomFrame = false
    private weak var previewFrames: PreviewFrameStore?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        let rootLayer = CALayer()
        let disabledActions = ["bounds": NSNull(),
                               "position": NSNull(),
                               "contents": NSNull()]
        rootLayer.actions = disabledActions
        rootLayer.backgroundColor = NSColor.clear.cgColor
        rootLayer.masksToBounds = false
        rootLayer.shadowColor = NSColor.black.cgColor
        rootLayer.shadowOpacity = 0.25
        rootLayer.shadowRadius = 24
        rootLayer.shadowOffset = CGSize(width: 0, height: -8)
        layer = rootLayer

        compositedLayer.contentsGravity = .resizeAspect
        compositedLayer.masksToBounds = false
        compositedLayer.isOpaque = false
        compositedLayer.isHidden = true
        compositedLayer.actions = disabledActions

        rootLayer.addSublayer(compositedLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(profile: DeviceProfile,
                   customFrame: CustomFrame?,
                   previewFrames: PreviewFrameStore) {
        if self.previewFrames !== previewFrames {
            self.previewFrames?.imageHandler = nil
            self.previewFrames = previewFrames
            previewFrames.imageHandler = { [weak self] image in
                self?.displayCompositedPreview(image)
            }
        }

        self.profile = profile
        hasCustomFrame = customFrame != nil
        compositedLayer.isHidden = compositedLayer.contents == nil

        updateBackingScale()
        needsLayout = true
    }

    func detachPreview() {
        previewFrames?.imageHandler = nil
        previewFrames = nil
    }

    private func displayCompositedPreview(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        compositedLayer.contents = image
        compositedLayer.isHidden = image == nil
        CATransaction.commit()
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

        compositedLayer.frame = bounds

        if hasCustomFrame {
            let shadowRadius = min(bounds.width, bounds.height) * 0.08
            layer?.shadowPath = CGPath(roundedRect: bounds,
                                       cornerWidth: shadowRadius,
                                       cornerHeight: shadowRadius,
                                       transform: nil)
        } else {
            let scale = min(bounds.width / profile.screenSize.width,
                            bounds.height / profile.screenSize.height)
            let shadowRadius = profile.screenCornerRadius * scale
            layer?.shadowPath = CGPath(roundedRect: bounds,
                                       cornerWidth: shadowRadius,
                                       cornerHeight: shadowRadius,
                                       transform: nil)
        }

        CATransaction.commit()
    }

    private func updateBackingScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        compositedLayer.contentsScale = scale
    }
}
