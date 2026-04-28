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
        let outputSize = customFrame != nil ? profile.frameSize : profile.screenSize
        let image = NSImage(size: outputSize)
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

    /// Without a custom bezel, the result is the rounded-clipped screen at
    /// `screenSize`. With a custom bezel, the screen is positioned at
    /// `screenOffset` inside a `frameSize` canvas with the bezel composited
    /// on top.
    private func compositeImage(buffer: CVPixelBuffer,
                                profile: DeviceProfile,
                                customFrame: CIImage?) -> CIImage? {
        let videoCI = CIImage(cvPixelBuffer: buffer)
        let videoExtent = videoCI.extent
        guard videoExtent.width > 0, videoExtent.height > 0 else { return nil }

        let scaleX = profile.screenSize.width / videoExtent.width
        let scaleY = profile.screenSize.height / videoExtent.height
        let scaled = videoCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        if let customFrame {
            // CG y-up: flip screenOffset.y so the screen sits at the top of
            // the frame canvas.
            let tx = profile.screenOffset.x
            let ty = profile.frameSize.height - profile.screenOffset.y - profile.screenSize.height
            let positioned = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))

            let screenRect = CGRect(x: tx, y: ty,
                                    width: profile.screenSize.width,
                                    height: profile.screenSize.height)
            guard let mask = roundedMask(rect: screenRect, radius: profile.screenCornerRadius) else { return nil }
            let maskedVideo = positioned.applyingFilter("CISourceInCompositing",
                                                        parameters: [kCIInputBackgroundImageKey: mask])
            return customFrame.composited(over: maskedVideo)
        } else {
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
