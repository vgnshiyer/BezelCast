@preconcurrency import AVFoundation
import AppKit
import CoreImage

struct BezelRenderer {
    let ciContext: CIContext

    func screenshot(from buffer: CVPixelBuffer,
                    profile: DeviceProfile,
                    customFrame: CIImage?) -> NSImage? {
        guard let composite = compositeImage(buffer: buffer, profile: profile, customFrame: customFrame),
              let cg = ciContext.createCGImage(composite, from: composite.extent) else { return nil }
        let image = NSImage(size: profile.frameSize)
        image.addRepresentation(NSBitmapImageRep(cgImage: cg))
        return image
    }

    func composite(video buffer: CVPixelBuffer,
                   profile: DeviceProfile,
                   customFrame: CIImage?,
                   into output: CVPixelBuffer) {
        guard let composite = compositeImage(buffer: buffer, profile: profile, customFrame: customFrame) else { return }
        ciContext.render(composite, to: output)
    }

    /// Builds the composite CIImage at the profile's frame coordinates.
    /// If customFrame is provided, uses it as the bezel art on top of the masked video.
    /// Otherwise renders our programmatic black bezel via CGContext.
    private func compositeImage(buffer: CVPixelBuffer,
                                profile: DeviceProfile,
                                customFrame: CIImage?) -> CIImage? {
        let videoCI = CIImage(cvPixelBuffer: buffer)
        let videoExtent = videoCI.extent
        guard videoExtent.width > 0, videoExtent.height > 0 else { return nil }

        let scaleX = profile.screenSize.width / videoExtent.width
        let scaleY = profile.screenSize.height / videoExtent.height
        let scaled = videoCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let tx = profile.screenOffset.x
        let ty = profile.frameSize.height - profile.screenOffset.y - profile.screenSize.height
        let positioned = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        let screenRect = CGRect(x: tx, y: ty,
                                width: profile.screenSize.width,
                                height: profile.screenSize.height)
        let maskFilter = CIFilter(name: "CIRoundedRectangleGenerator")!
        maskFilter.setValue(CIVector(cgRect: screenRect), forKey: kCIInputExtentKey)
        maskFilter.setValue(profile.screenCornerRadius, forKey: "inputRadius")
        maskFilter.setValue(CIColor.white, forKey: kCIInputColorKey)
        guard let mask = maskFilter.outputImage else { return nil }

        let maskedVideo = positioned.applyingFilter("CISourceInCompositing",
                                                    parameters: [kCIInputBackgroundImageKey: mask])

        if let customFrame {
            return customFrame.composited(over: maskedVideo)
        } else {
            guard let programmatic = programmaticBezelImage(profile: profile) else { return nil }
            return programmatic.composited(over: maskedVideo)
        }
    }

    /// Renders a thin black ring around the screen + Dynamic Island into a CIImage
    /// the same size as profile.frameSize. Transparent everywhere else.
    private func programmaticBezelImage(profile: DeviceProfile) -> CIImage? {
        let width = Int(profile.frameSize.width)
        let height = Int(profile.frameSize.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let thickness = DefaultBezelArt.thickness
        let overlap = DefaultBezelArt.edgeOverlap
        let innerY = profile.frameSize.height - profile.screenOffset.y - profile.screenSize.height
        let screenRect = CGRect(x: profile.screenOffset.x, y: innerY,
                                width: profile.screenSize.width, height: profile.screenSize.height)
        let bezelOuter = screenRect.insetBy(dx: -thickness, dy: -thickness)
        let bezelInner = screenRect.insetBy(dx: overlap, dy: overlap)
        let outerCorner = profile.screenCornerRadius + thickness
        let innerCorner = max(profile.screenCornerRadius - overlap, 0)

        let combined = CGMutablePath()
        combined.addPath(CGPath(roundedRect: bezelOuter,
                                cornerWidth: outerCorner, cornerHeight: outerCorner, transform: nil))
        combined.addPath(CGPath(roundedRect: bezelInner,
                                cornerWidth: innerCorner, cornerHeight: innerCorner, transform: nil))

        ctx.setFillColor(DefaultBezelArt.color.cgColor)
        ctx.addPath(combined)
        ctx.fillPath(using: .evenOdd)

        if let island = profile.island {
            let islandY = profile.frameSize.height - profile.screenOffset.y - island.origin.y - island.height
            let islandRect = CGRect(x: profile.screenOffset.x + island.origin.x,
                                    y: islandY,
                                    width: island.width, height: island.height)
            ctx.addPath(CGPath(roundedRect: islandRect,
                               cornerWidth: island.height / 2, cornerHeight: island.height / 2, transform: nil))
            ctx.fillPath()
        }

        if let notch = profile.notch {
            let notchTop = profile.frameSize.height - profile.screenOffset.y
            let notchRect = CGRect(
                x: profile.screenOffset.x + (profile.screenSize.width - notch.width) / 2,
                y: notchTop - notch.height,
                width: notch.width,
                height: notch.height)
            ctx.addPath(notchPath(rect: notchRect))
            ctx.fillPath()
        }

        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg)
    }

    /// Notch path for the bitmap context (CG y-up). Flat top edge attached
    /// to rect.maxY, two rounded corners on the bottom of radius half-height.
    private func notchPath(rect: CGRect) -> CGPath {
        let r = rect.height / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.minY),
                    radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
                    radius: r)
        path.closeSubpath()
        return path
    }
}
