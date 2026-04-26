@preconcurrency import AVFoundation
import AppKit
import CoreImage

struct BezelGeometry {
    let videoSize: CGSize

    private var rawOuterWidth: CGFloat { videoSize.width + 2 * frameThickness }
    private var rawOuterHeight: CGFloat { videoSize.height + 2 * frameThickness }

    var frameThickness: CGFloat { videoSize.width * 0.026 }
    var outerWidth: CGFloat { (rawOuterWidth / 2).rounded() * 2 }
    var outerHeight: CGFloat { (rawOuterHeight / 2).rounded() * 2 }
    var outerSize: CGSize { CGSize(width: outerWidth, height: outerHeight) }
    var outerCorner: CGFloat { outerWidth * 0.16 }
    var innerCorner: CGFloat { max(outerCorner - frameThickness, 0) }
    var islandWidth: CGFloat { outerWidth * 0.32 }
    var islandHeight: CGFloat { outerWidth * 0.096 }
    var islandTopOffset: CGFloat { frameThickness + outerWidth * 0.025 }
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

        // Bezel ring: outer rounded rect minus inner rounded rect, even-odd fill
        let combined = CGMutablePath()
        combined.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: g.outerSize),
                                cornerWidth: g.outerCorner, cornerHeight: g.outerCorner, transform: nil))
        combined.addPath(CGPath(roundedRect: CGRect(x: g.frameThickness, y: g.frameThickness,
                                                    width: videoSize.width, height: videoSize.height),
                                cornerWidth: g.innerCorner, cornerHeight: g.innerCorner, transform: nil))

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(combined)
        ctx.fillPath(using: .evenOdd)

        // Dynamic island
        let islandRect = CGRect(x: (g.outerWidth - g.islandWidth) / 2,
                                y: g.outerHeight - g.islandTopOffset - g.islandHeight,
                                width: g.islandWidth, height: g.islandHeight)
        ctx.addPath(CGPath(roundedRect: islandRect,
                           cornerWidth: g.islandHeight / 2, cornerHeight: g.islandHeight / 2, transform: nil))
        ctx.fillPath()

        return ctx.makeImage()
    }

    func composite(video buffer: CVPixelBuffer,
                   chrome: CIImage,
                   geometry g: BezelGeometry,
                   into output: CVPixelBuffer) {
        let videoCI = CIImage(cvPixelBuffer: buffer)
            .transformed(by: CGAffineTransform(translationX: g.frameThickness, y: g.frameThickness))
        let composite = chrome.composited(over: videoCI)
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

        let islandRect = CGRect(x: (g.outerWidth - g.islandWidth) / 2,
                                y: g.outerHeight - g.islandTopOffset - g.islandHeight,
                                width: g.islandWidth, height: g.islandHeight)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: islandRect,
                           cornerWidth: g.islandHeight / 2, cornerHeight: g.islandHeight / 2, transform: nil))
        ctx.fillPath()
    }
}
