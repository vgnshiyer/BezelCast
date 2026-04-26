@preconcurrency import AVFoundation
import AppKit
import CoreImage

struct BezelGeometry {
    static let frameRatio: CGFloat = 0.025
    static let cornerRatio: CGFloat = 0.16
    static let islandWidthRatio: CGFloat = 0.32
    static let islandHeightRatio: CGFloat = 0.09
    static let islandTopRatio: CGFloat = 0.03

    let videoSize: CGSize

    private var rawOuterWidth: CGFloat { videoSize.width / (1 - 2 * Self.frameRatio) }
    private var rawOuterHeight: CGFloat { videoSize.height + 2 * frameThickness }

    var outerWidth: CGFloat { (rawOuterWidth / 2).rounded() * 2 }
    var outerHeight: CGFloat { (rawOuterHeight / 2).rounded() * 2 }
    var outerSize: CGSize { CGSize(width: outerWidth, height: outerHeight) }
    var frameThickness: CGFloat { outerWidth * Self.frameRatio }
    var outerCorner: CGFloat { outerWidth * Self.cornerRatio }
    var innerCorner: CGFloat { max(outerCorner - frameThickness, 0) }

    var innerRect: CGRect {
        CGRect(x: frameThickness, y: frameThickness,
               width: videoSize.width, height: videoSize.height)
    }

    var islandRect: CGRect {
        let w = videoSize.width * Self.islandWidthRatio
        let h = videoSize.width * Self.islandHeightRatio
        let topOffset = videoSize.width * Self.islandTopRatio
        return CGRect(x: (outerWidth - w) / 2,
                      y: outerHeight - frameThickness - topOffset - h,
                      width: w, height: h)
    }
}

struct BezelRenderer {
    let ciContext: CIContext

    func screenshot(from buffer: CVPixelBuffer) -> NSImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        guard ci.extent.width > 0, ci.extent.height > 0,
              let cgVideo = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        let g = BezelGeometry(videoSize: ci.extent.size)

        let image = NSImage(size: g.outerSize)
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
        drawFullBezel(in: ctx, geometry: g, video: cgVideo)
        return image
    }

    /// Solid black rounded device shape, alpha 1 inside, alpha 0 outside.
    /// Acts as the underlay for the recording so alpha is 1 across the
    /// entire rounded device — no anti-aliasing gap at the screen edge.
    func backplateImage(for videoSize: CGSize) -> CGImage? {
        let g = BezelGeometry(videoSize: videoSize)
        let width = Int(g.outerWidth)
        let height = Int(g.outerHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: g.outerSize),
                           cornerWidth: g.outerCorner, cornerHeight: g.outerCorner, transform: nil))
        ctx.fillPath()

        return ctx.makeImage()
    }

    /// Alpha mask: opaque inside the rounded screen *minus* the Dynamic
    /// Island (so the island shows the backplate through). Used to clip
    /// the video so it can't leak past the rounded device edge.
    func screenMaskImage(for videoSize: CGSize) -> CGImage? {
        let g = BezelGeometry(videoSize: videoSize)
        let width = Int(g.outerWidth)
        let height = Int(g.outerHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addPath(CGPath(roundedRect: g.innerRect,
                           cornerWidth: g.innerCorner, cornerHeight: g.innerCorner, transform: nil))
        ctx.fillPath()

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: g.islandRect,
                           cornerWidth: g.islandRect.height / 2, cornerHeight: g.islandRect.height / 2, transform: nil))
        ctx.clip()
        ctx.clear(g.islandRect)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    func composite(video buffer: CVPixelBuffer,
                   backplate: CIImage,
                   mask: CIImage,
                   geometry g: BezelGeometry,
                   into output: CVPixelBuffer) {
        let videoCI = CIImage(cvPixelBuffer: buffer)
            .transformed(by: CGAffineTransform(translationX: g.frameThickness, y: g.frameThickness))
        let maskedVideo = videoCI.applyingFilter("CISourceInCompositing",
                                                 parameters: [kCIInputBackgroundImageKey: mask])
        let composite = maskedVideo.composited(over: backplate)
        ciContext.render(composite, to: output)
    }

    private func drawFullBezel(in ctx: CGContext, geometry g: BezelGeometry, video: CGImage) {
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: g.outerSize),
                           cornerWidth: g.outerCorner, cornerHeight: g.outerCorner, transform: nil))
        ctx.fillPath()

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: g.innerRect, cornerWidth: g.innerCorner, cornerHeight: g.innerCorner, transform: nil))
        ctx.clip()
        ctx.draw(video, in: g.innerRect)
        ctx.restoreGState()

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: g.islandRect,
                           cornerWidth: g.islandRect.height / 2, cornerHeight: g.islandRect.height / 2, transform: nil))
        ctx.fillPath()
    }
}
