import AppKit
import CoreGraphics
import CoreImage

struct FrameGeometry: Equatable, Sendable {
    let frameSize: CGSize
    /// Screen cutout in frame pixels, using image coordinates (origin at top-left).
    let screenRect: CGRect
}

struct CustomFrame: @unchecked Sendable {
    let name: String
    private let portraitFrame: OrientedFrame?
    private let landscapeFrame: OrientedFrame?
    private let currentFrame: OrientedFrame

    var image: NSImage { currentFrame.image }
    var renderFrame: RenderFrame { currentFrame.renderFrame }

    var geometry: FrameGeometry { renderFrame.geometry }

    static func make(name: String,
                     image: NSImage,
                     cgImage: CGImage,
                     geometry: FrameGeometry,
                     profile: DeviceProfile) -> CustomFrame? {
        let sourceFrame = OrientedFrame(image: image,
                                        renderFrame: RenderFrame(image: CIImage(cgImage: cgImage),
                                                                 geometry: geometry))
        let sourceIsLandscape = geometry.screenRect.width > geometry.screenRect.height
        let portraitFrame: OrientedFrame?
        let landscapeFrame: OrientedFrame?

        if sourceIsLandscape {
            guard let rotated = rotatedFrame(from: cgImage, geometry: geometry, clockwise: false) else {
                return nil
            }
            portraitFrame = rotated
            landscapeFrame = sourceFrame
        } else {
            guard let rotated = rotatedFrame(from: cgImage, geometry: geometry, clockwise: true) else {
                return nil
            }
            portraitFrame = sourceFrame
            landscapeFrame = rotated
        }

        return CustomFrame(name: name,
                           portraitFrame: portraitFrame,
                           landscapeFrame: landscapeFrame,
                           currentFrame: sourceFrame)
            .oriented(to: profile)
    }

    func oriented(to profile: DeviceProfile) -> CustomFrame? {
        guard let nextFrame = profile.isLandscape ? landscapeFrame : portraitFrame,
              nextFrame.geometry.screenRect.matches(profile.screenSize) else { return nil }
        return CustomFrame(name: name,
                           portraitFrame: portraitFrame,
                           landscapeFrame: landscapeFrame,
                           currentFrame: nextFrame)
    }

    private static func rotatedFrame(from image: CGImage,
                                     geometry: FrameGeometry,
                                     clockwise: Bool) -> OrientedFrame? {
        guard let rotatedCGImage = rotatedImage(image, clockwise: clockwise) else { return nil }
        let rotatedGeometry = geometry.rotated(clockwise: clockwise)
        let rotatedImage = NSImage(cgImage: rotatedCGImage, size: rotatedGeometry.frameSize)

        return OrientedFrame(image: rotatedImage,
                             renderFrame: RenderFrame(image: CIImage(cgImage: rotatedCGImage),
                                                      geometry: rotatedGeometry))
    }

    private static func rotatedImage(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = height * bytesPerPixel
        guard height <= Int.max / bytesPerPixel,
              width <= Int.max / bytesPerRow,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: height,
                                      height: width,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                          | CGBitmapInfo.byteOrder32Big.rawValue) else {
            return nil
        }

        context.translateBy(x: CGFloat(height) / 2, y: CGFloat(width) / 2)
        context.rotate(by: clockwise ? .pi / 2 : -.pi / 2)
        context.draw(image,
                     in: CGRect(x: -CGFloat(width) / 2,
                                y: -CGFloat(height) / 2,
                                width: CGFloat(width),
                                height: CGFloat(height)))
        return context.makeImage()
    }
}

private struct OrientedFrame: @unchecked Sendable {
    let image: NSImage
    let renderFrame: RenderFrame

    var geometry: FrameGeometry { renderFrame.geometry }
}

struct RenderFrame: @unchecked Sendable {
    let image: CIImage
    let geometry: FrameGeometry
}

enum CustomFrameDetector {
    static func screenRect(in image: CGImage, alphaThreshold: UInt8 = 16) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              width <= Int.max / height,
              let rgba = rgbaBytes(from: image) else { return nil }

        let pixelCount = width * height
        var visited = [Bool](repeating: false, count: pixelCount)

        func isTransparent(_ index: Int) -> Bool {
            rgba[index * 4 + 3] <= alphaThreshold
        }

        func enqueue(_ index: Int, into queue: inout [Int]) {
            guard !visited[index], isTransparent(index) else { return }
            visited[index] = true
            queue.append(index)
        }

        func floodFill(from start: Int) -> (count: Int, rect: CGRect) {
            var queue = [start]
            var cursor = 0
            var count = 0
            var minX = width
            var minY = height
            var maxX = 0
            var maxY = 0
            visited[start] = true

            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                count += 1

                let x = index % width
                let y = index / width
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)

                if x > 0 { enqueue(index - 1, into: &queue) }
                if x + 1 < width { enqueue(index + 1, into: &queue) }
                if y > 0 { enqueue(index - width, into: &queue) }
                if y + 1 < height { enqueue(index + width, into: &queue) }
            }

            let rect = CGRect(x: minX,
                              y: minY,
                              width: maxX - minX + 1,
                              height: maxY - minY + 1)
            return (count, rect)
        }

        // First remove transparent background connected to the canvas edge.
        var edgeQueue: [Int] = []
        edgeQueue.reserveCapacity(width * 2 + height * 2)
        for x in 0..<width {
            enqueue(x, into: &edgeQueue)
            enqueue((height - 1) * width + x, into: &edgeQueue)
        }
        for y in 0..<height {
            enqueue(y * width, into: &edgeQueue)
            enqueue(y * width + width - 1, into: &edgeQueue)
        }
        var edgeCursor = 0
        while edgeCursor < edgeQueue.count {
            let index = edgeQueue[edgeCursor]
            edgeCursor += 1
            let x = index % width
            let y = index / width
            if x > 0 { enqueue(index - 1, into: &edgeQueue) }
            if x + 1 < width { enqueue(index + 1, into: &edgeQueue) }
            if y > 0 { enqueue(index - width, into: &edgeQueue) }
            if y + 1 < height { enqueue(index + width, into: &edgeQueue) }
        }

        var best: (count: Int, rect: CGRect)?
        for index in 0..<pixelCount where !visited[index] && isTransparent(index) {
            let component = floodFill(from: index)
            if best == nil || component.count > best!.count {
                best = component
            }
        }

        guard let best,
              best.rect.width >= CGFloat(width) * 0.25,
              best.rect.height >= CGFloat(height) * 0.25 else { return nil }
        return best.rect
    }

    private static func rgbaBytes(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        guard width > 0, height > 0,
              width <= Int.max / bytesPerPixel else { return nil }
        let bytesPerRow = width * bytesPerPixel
        guard height <= Int.max / bytesPerRow else { return nil }
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)

        let ok = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                              | CGBitmapInfo.byteOrder32Big.rawValue) else {
                return false
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return ok ? rgba : nil
    }
}

extension FrameGeometry {
    func rotated(clockwise: Bool) -> FrameGeometry {
        let rect = screenRect
        let rotatedRect: CGRect

        if clockwise {
            rotatedRect = CGRect(x: frameSize.height - rect.maxY,
                                 y: rect.minX,
                                 width: rect.height,
                                 height: rect.width)
        } else {
            rotatedRect = CGRect(x: rect.minY,
                                 y: frameSize.width - rect.maxX,
                                 width: rect.height,
                                 height: rect.width)
        }

        return FrameGeometry(frameSize: CGSize(width: frameSize.height, height: frameSize.width),
                             screenRect: rotatedRect)
    }
}

extension CGRect {
    func hasAspect(of size: CGSize, tolerance: CGFloat = 0.025) -> Bool {
        let target = min(size.width, size.height) / max(size.width, size.height)
        let candidate = min(width, height) / max(width, height)
        return abs(candidate - target) <= tolerance
    }

    func matches(_ size: CGSize, tolerance: CGFloat = 0.025) -> Bool {
        let sameOrientation = (width > height) == (size.width > size.height)
        return sameOrientation && hasAspect(of: size, tolerance: tolerance)
    }
}
