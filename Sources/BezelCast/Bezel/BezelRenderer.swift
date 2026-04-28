import AppKit
import CoreImage
import CoreVideo

struct BezelRenderer {
    let ciContext: CIContext

    func screenshot(from buffer: CVPixelBuffer,
                    profile: DeviceProfile,
                    customFrame: RenderFrame?) -> NSImage? {
        guard let composite = compositeImage(buffer: buffer, profile: profile, customFrame: customFrame),
              let cg = ciContext.createCGImage(composite, from: composite.extent) else { return nil }
        let outputSize = customFrame?.geometry.frameSize ?? profile.screenSize
        let image = NSImage(size: outputSize)
        image.addRepresentation(NSBitmapImageRep(cgImage: cg))
        return image
    }

    func previewImage(from buffer: CVPixelBuffer,
                      profile: DeviceProfile,
                      customFrame: RenderFrame?,
                      maxLongSide: CGFloat = 1800) -> CGImage? {
        guard let composite = compositeImage(buffer: buffer,
                                             profile: profile,
                                             customFrame: customFrame,
                                             customScreenBleed: customFrame == nil ? 0 : 2) else { return nil }
        let extent = composite.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let scale = min(1, maxLongSide / max(extent.width, extent.height))
        let output = scale < 1
            ? composite.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : composite
        return ciContext.createCGImage(output, from: output.extent)
    }

    func composite(video buffer: CVPixelBuffer,
                   profile: DeviceProfile,
                   customFrame: RenderFrame?,
                   into output: CVPixelBuffer) {
        guard let composite = compositeImage(buffer: buffer, profile: profile, customFrame: customFrame) else { return }
        let outputRect = CGRect(x: 0,
                                y: 0,
                                width: CVPixelBufferGetWidth(output),
                                height: CVPixelBufferGetHeight(output))
        ciContext.render(composite.fitted(in: outputRect), to: output)
    }

    /// Without a custom bezel, the result is the rounded-clipped screen at
    /// `screenSize`. With a custom bezel, the screen is positioned inside the
    /// detected transparent cutout with the bezel composited on top.
    private func compositeImage(buffer: CVPixelBuffer,
                                profile: DeviceProfile,
                                customFrame: RenderFrame?,
                                customScreenBleed: CGFloat = 0) -> CIImage? {
        let videoCI = CIImage(cvPixelBuffer: buffer)
        let videoExtent = videoCI.extent
        guard videoExtent.width > 0, videoExtent.height > 0 else { return nil }

        if let customFrame {
            let geometry = customFrame.geometry
            let screenRectTopLeft = geometry.screenRect
            let scaleX = screenRectTopLeft.width / videoExtent.width
            let scaleY = screenRectTopLeft.height / videoExtent.height
            let scaled = videoCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            // CG y-up: flip screenOffset.y so the screen sits at the top of
            // the frame canvas.
            let tx = screenRectTopLeft.minX
            let ty = geometry.frameSize.height - screenRectTopLeft.minY - screenRectTopLeft.height
            let positioned = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))

            let screenRect = CGRect(x: tx, y: ty,
                                    width: screenRectTopLeft.width,
                                    height: screenRectTopLeft.height)
            let maskRect = screenRect.bleeding(by: customScreenBleed,
                                               inside: CGRect(origin: .zero, size: geometry.frameSize))
            let cornerRadius = profile.scaledCornerRadius(for: screenRect.size) + max(0, customScreenBleed)
            guard let mask = roundedMask(rect: maskRect,
                                         radius: cornerRadius) else { return nil }
            let video = customScreenBleed > 0
                ? positioned.clampedToExtent().cropped(to: maskRect)
                : positioned
            let maskedVideo = video.applyingFilter("CISourceInCompositing",
                                                   parameters: [kCIInputBackgroundImageKey: mask])
            return customFrame.image.composited(over: maskedVideo)
        } else {
            let scaleX = profile.screenSize.width / videoExtent.width
            let scaleY = profile.screenSize.height / videoExtent.height
            let scaled = videoCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            let screenRect = CGRect(x: 0, y: 0,
                                    width: profile.screenSize.width,
                                    height: profile.screenSize.height)
            guard let mask = roundedMask(rect: screenRect, radius: profile.screenCornerRadius) else { return nil }
            return scaled.applyingFilter("CISourceInCompositing",
                                         parameters: [kCIInputBackgroundImageKey: mask])
        }
    }

    private func roundedMask(rect: CGRect, radius: CGFloat) -> CIImage? {
        let filter = CIFilter(name: "CIRoundedRectangleGenerator")!
        filter.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(CIColor.white, forKey: kCIInputColorKey)
        return filter.outputImage
    }
}

private extension CIImage {
    func fitted(in target: CGRect) -> CIImage {
        guard extent.width > 0, extent.height > 0 else { return self }

        let scale = min(target.width / extent.width, target.height / extent.height)
        let scaledSize = CGSize(width: extent.width * scale, height: extent.height * scale)
        let tx = target.midX - scaledSize.width / 2 - extent.minX * scale
        let ty = target.midY - scaledSize.height / 2 - extent.minY * scale
        let fitted = transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: tx, y: ty))
        let clear = CIImage(color: .clear).cropped(to: target)
        return fitted.composited(over: clear).cropped(to: target)
    }
}

private extension CGRect {
    func bleeding(by amount: CGFloat, inside bounds: CGRect) -> CGRect {
        guard amount > 0 else { return self }
        let expanded = insetBy(dx: -amount, dy: -amount)
        let bounded = expanded.intersection(bounds)
        return bounded.isNull ? self : bounded
    }
}
