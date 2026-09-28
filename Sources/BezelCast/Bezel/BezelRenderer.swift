import AppKit
import CoreImage
import CoreVideo

struct BezelRenderer {
    let ciContext: CIContext

    func screenshot(from buffer: CVPixelBuffer,
                    profile: DeviceProfile,
                    customFrame: RenderFrame?,
                    presentation: CapturePresentation = .init()) -> NSImage? {
        guard let device = compositeImage(buffer: buffer, profile: profile, customFrame: customFrame) else { return nil }
        let composite = presented(device, presentation: presentation, animated: false)
        guard let cg = ciContext.createCGImage(composite, from: composite.extent) else { return nil }
        let outputSize = composite.extent.size
        let image = NSImage(size: outputSize)
        image.addRepresentation(NSBitmapImageRep(cgImage: cg))
        return image
    }

    func previewImage(from buffer: CVPixelBuffer,
                      profile: DeviceProfile,
                      customFrame: RenderFrame?,
                      presentation: CapturePresentation = .init(),
                      maxLongSide: CGFloat = 1800) -> CGImage? {
        guard let device = compositeImage(buffer: buffer,
                                          profile: profile,
                                          customFrame: customFrame) else { return nil }
        let composite = presented(device, presentation: presentation, animated: true)
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
                   presentation: CapturePresentation = .init(),
                   into output: CVPixelBuffer) {
        guard let device = compositeImage(buffer: buffer, profile: profile, customFrame: customFrame) else { return }
        let outputRect = CGRect(x: 0,
                                y: 0,
                                width: CVPixelBufferGetWidth(output),
                                height: CVPixelBufferGetHeight(output))
        var fixedPresentation = presentation
        fixedPresentation.fixedCanvasSize = outputRect.size
        let composite = presented(device, presentation: fixedPresentation, animated: true)
        ciContext.render(composite, to: output)
    }

    /// Without a custom bezel, the result is the rounded-clipped screen at
    /// `screenSize`. With a custom bezel, the screen is positioned inside the
    /// detected transparent cutout with the bezel composited on top.
    private func compositeImage(buffer: CVPixelBuffer,
                                profile: DeviceProfile,
                                customFrame: RenderFrame?) -> CIImage? {
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
            // Two independently antialiased edges leave a translucent seam
            // when composited. Extend captured edge pixels underneath the
            // opaque bezel for every output, without scaling or cropping the
            // visible screen. Keep the rounded corner centers unchanged.
            let screenOverlap: CGFloat = 2
            let maskRect = screenRect.bleeding(by: screenOverlap,
                                               inside: CGRect(origin: .zero, size: geometry.frameSize))
            let cornerRadius = profile.scaledCornerRadius(for: screenRect.size) + screenOverlap
            guard let mask = roundedMask(rect: maskRect,
                                         radius: cornerRadius) else { return nil }
            let video = positioned.clampedToExtent().cropped(to: maskRect)
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

    private func presented(_ device: CIImage,
                           presentation: CapturePresentation,
                           animated: Bool) -> CIImage {
        // Keep the transparent/native path unchanged, including its pixel dimensions.
        if presentation.background.isNone && presentation.fixedCanvasSize == nil { return device }

        let canvas = CGRect(origin: .zero, size: presentation.outputSize(for: device.extent.size))
        let deviceRect = presentation.deviceRect(for: device.extent.size)
        // Define transparent pixels across the canvas before sharing this image
        // with the blur branch. A device-only extent can leak screen color into
        // the background when Core Image combines the two render regions.
        let fitted = device.fitted(in: deviceRect)
            .composited(over: CIImage(color: .clear).cropped(to: canvas))
        var background = backgroundImage(presentation.background, in: canvas)
        if animated, let previous = presentation.previousBackground,
           presentation.backgroundTransitionProgress < 1 {
            background = backgroundImage(previous, in: canvas).applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: background,
                kCIInputTimeKey: presentation.backgroundTransitionProgress,
            ]).cropped(to: canvas)
        }

        if presentation.shadow && !presentation.background.isNone {
            let shortSide = min(canvas.width, canvas.height)
            let shadow = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.28))
                .cropped(to: canvas)
                .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: fitted])
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: shortSide * 0.014])
                .transformed(by: CGAffineTransform(translationX: 0, y: -shortSide * 0.012))
                .cropped(to: canvas)
            background = shadow.composited(over: background)
        }
        return fitted.composited(over: background).cropped(to: canvas)
    }

    /// Core Image keeps these layers on the GPU. Imported images are decoded once
    /// by the background library; no AppKit drawing or image decoding runs per frame.
    private func backgroundImage(_ background: CaptureBackground, in canvas: CGRect) -> CIImage {
        switch background.content {
        case .none:
            return CIImage(color: .clear).cropped(to: canvas)
        case .solid(let color):
            return CIImage(color: color.ciColor).cropped(to: canvas)
        case .gradient(let first, let second):
            return CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: canvas.minX, y: canvas.maxY),
                "inputPoint1": CIVector(x: canvas.maxX, y: canvas.minY),
                "inputColor0": first.ciColor,
                "inputColor1": second.ciColor,
            ])!.outputImage!.cropped(to: canvas)
        case .image(let image):
            return CIImage(cgImage: image).filled(in: canvas)
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

private extension BackgroundColor {
    var ciColor: CIColor { CIColor(red: red, green: green, blue: blue, alpha: 1) }
}

private extension CIImage {
    func filled(in target: CGRect) -> CIImage {
        let scale = max(target.width / extent.width, target.height / extent.height)
        let tx = target.midX - extent.midX * scale
        let ty = target.midY - extent.midY * scale
        return transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: tx, y: ty))
            .cropped(to: target)
    }

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
