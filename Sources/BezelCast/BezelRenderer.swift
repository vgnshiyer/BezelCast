@preconcurrency import AVFoundation
import AppKit
import CoreImage

struct BezelGeometry {
    static let frameRatio: CGFloat = 0.025
    static let cornerRatio: CGFloat = 0.16

    let videoSize: CGSize

    private var rawOuterWidth: CGFloat { videoSize.width / (1 - 2 * Self.frameRatio) }
    private var rawOuterHeight: CGFloat { videoSize.height + 2 * frameThickness }

    var outerWidth: CGFloat { (rawOuterWidth / 2).rounded() * 2 }
    var outerHeight: CGFloat { (rawOuterHeight / 2).rounded() * 2 }
    var outerSize: CGSize { CGSize(width: outerWidth, height: outerHeight) }
    var frameThickness: CGFloat { outerWidth * Self.frameRatio }
    var outerCorner: CGFloat { outerWidth * Self.cornerRatio }
    var innerCorner: CGFloat { max(outerCorner - frameThickness, 0) }
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

    func chromeImage(for videoSize: CGSize) -> CGImage? {
        let g = BezelGeometry(videoSize: videoSize)
        let width = Int(g.outerWidth)
        let height = Int(g.outerHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // Bezel ring: outer rounded rect minus inner rounded rect, even-odd fill.
        let combined = CGMutablePath()
        combined.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: g.outerSize),
                                cornerWidth: g.outerCorner, cornerHeight: g.outerCorner, transform: nil))
        combined.addPath(CGPath(roundedRect: CGRect(x: g.frameThickness, y: g.frameThickness,
                                                    width: videoSize.width, height: videoSize.height),
                                cornerWidth: g.innerCorner, cornerHeight: g.innerCorner, transform: nil))

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(combined)
        ctx.fillPath(using: .evenOdd)

        return ctx.makeImage()
    }

    func composite(video buffer: CVPixelBuffer,
                   chrome: CIImage,
                   geometry g: BezelGeometry,
                   into output: CVPixelBuffer) {
        let outputRect = CGRect(origin: .zero, size: g.outerSize)
        let bg = CIImage(color: .black).cropped(to: outputRect)
        let videoCI = CIImage(cvPixelBuffer: buffer)
            .transformed(by: CGAffineTransform(translationX: g.frameThickness, y: g.frameThickness))
        let composite = chrome.composited(over: videoCI.composited(over: bg))
        ciContext.render(composite, to: output)
    }

    private func drawFullBezel(in ctx: CGContext, geometry g: BezelGeometry, video: CGImage) {
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: g.outerSize),
                           cornerWidth: g.outerCorner, cornerHeight: g.outerCorner, transform: nil))
        ctx.fillPath()

        let innerRect = CGRect(x: g.frameThickness, y: g.frameThickness,
                               width: g.videoSize.width, height: g.videoSize.height)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: innerRect, cornerWidth: g.innerCorner, cornerHeight: g.innerCorner, transform: nil))
        ctx.clip()
        ctx.draw(video, in: innerRect)
        ctx.restoreGState()
    }
}
