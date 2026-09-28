import AppKit
import CoreImage
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BezelCast

final class BezelEdgeAlignmentTests: XCTestCase {
    private let context = CIContext()

    func testBuiltInScreenshotsSealEveryScreenEdgeInBothOrientations() throws {
        try auditBuiltIns(previewLongSide: nil)
    }

    func testScaledBuiltInPreviewsSealEveryScreenEdgeInBothOrientations() throws {
        for longSide: CGFloat in [601, 1800] {
            try auditBuiltIns(previewLongSide: longSide)
        }
    }

    func testDifferentSourceResolutionStillSealsTheSelectedBezel() throws {
        for longSide: CGFloat? in [nil, 601, 1800] {
            try auditBuiltIns(previewLongSide: longSide, profileIDs: ["iphone-16", "iphone-12"],
                              capturedPortraitSize: CGSize(width: 1206, height: 2622))
        }
    }

    func testMovieCompositorSealsEdgesWithDifferentSourceResolution() throws {
        try auditBuiltIns(previewLongSide: nil,
                          profileIDs: ["iphone-17-pro", "iphone-16", "ipad-pro-13"],
                          capturedPortraitSize: CGSize(width: 1206, height: 2622), movie: true)
    }

    func testBrightCanvasDoesNotLeakThroughTheInnerBezelEdge() throws {
        let profile = try XCTUnwrap(DeviceProfile.catalog.first { $0.id == "iphone-17-pro" })
        let option = try XCTUnwrap(BezelLibrary.automatic(for: profile))
        let frame = try XCTUnwrap(BezelLibrary.frame(for: option, orientedTo: profile))
        let input = try whiteBuffer(CGSize(width: 1179, height: 2556))
        let renderer = BezelRenderer(ciContext: context)
        let screenshot = try XCTUnwrap(renderer.screenshot(from: input, profile: profile, customFrame: frame.renderFrame))
        let original = try XCTUnwrap(screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let margin: CGFloat = 100
        let canvas = CGSize(width: frame.geometry.frameSize.width + margin * 2,
                            height: frame.geometry.frameSize.height + margin * 2)
        let presentation = CapturePresentation(
            background: CaptureBackground(id: "edge-magenta", name: "Magenta",
                                           content: .solid(BackgroundColor(red: 1, green: 0, blue: 1))),
            padding: margin / canvas.width, shadow: false, fixedCanvasSize: canvas)
        let withBackground = try XCTUnwrap(renderer.screenshot(from: input, profile: profile,
                                                               customFrame: frame.renderFrame, presentation: presentation))
        let exported = try XCTUnwrap(withBackground.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let preview = try XCTUnwrap(renderer.previewImage(from: input, profile: profile,
                                                          customFrame: frame.renderFrame, presentation: presentation,
                                                          maxLongSide: canvas.height))
        let video = try buffer(canvas)
        renderer.composite(video: input, profile: profile, customFrame: frame.renderFrame,
                           presentation: presentation, into: video)
        let movie = try XCTUnwrap(context.createCGImage(CIImage(cvPixelBuffer: video),
                                                       from: CGRect(origin: .zero, size: canvas)))
        let expected = pixels(original)
        for (name, output) in [("screenshot", exported), ("preview", preview), ("movie", movie)] {
            let actual = pixels(output)
            var changed = 0, maximumError = 0
            forEachEdgePixel(width: original.width, height: original.height,
                             screen: frame.geometry.screenRect,
                             radius: profile.scaledCornerRadius(for: frame.geometry.screenRect.size), margin: 10) { x, y in
                let before = (y * original.width + x) * 4
                let after = ((y + Int(margin)) * output.width + x + Int(margin)) * 4
                var error = 0
                for channel in 0..<4 {
                    error = max(error, abs(Int(expected[before + channel]) - Int(actual[after + channel])))
                }
                if error > 1 { changed += 1 }
                maximumError = max(maximumError, error)
            }
            XCTAssertEqual(changed, 0, "\(name): \(changed) edge pixels changed against a bright canvas, maximum error \(maximumError)")
        }
    }

    private func auditBuiltIns(previewLongSide: CGFloat?, profileIDs: Set<String>? = nil,
                               capturedPortraitSize: CGSize? = nil, movie: Bool = false) throws {
        var seen: Set<String> = []
        let representatives = DeviceProfile.catalog.filter { profile in
            guard profileIDs?.contains(profile.id) ?? true else { return false }
            let key = "\(profile.family)|\(profile.screenSize)|\(profile.screenCornerRadius)|\(profile.displayCutout)"
            return seen.insert(key).inserted
        }
        if ProcessInfo.processInfo.environment["BEZELCAST_TEST_ARTIFACTS"] != nil {
            print("Edge audit: \(representatives.count) unique geometries × 2 orientations; preview=\(String(describing: previewLongSide)), cross-model=\(capturedPortraitSize != nil), movie=\(movie)")
        }
        let renderer = BezelRenderer(ciContext: context)
        for sourceProfile in representatives {
            for landscape in [false, true] {
                try autoreleasepool {
                    let profile = sourceProfile.oriented(matching: landscape
                        ? CGSize(width: sourceProfile.screenSize.height, height: sourceProfile.screenSize.width)
                        : sourceProfile.screenSize)
                    let option = try XCTUnwrap(BezelLibrary.automatic(for: sourceProfile))
                    let frame = try XCTUnwrap(BezelLibrary.frame(for: option, orientedTo: profile))
                    let sourceSize = capturedPortraitSize.map {
                        landscape ? CGSize(width: $0.height, height: $0.width) : $0
                    } ?? profile.screenSize
                    let input = try whiteBuffer(sourceSize)
                    let image: CGImage
                    if movie {
                        let output = try buffer(frame.geometry.frameSize)
                        renderer.composite(video: input, profile: profile, customFrame: frame.renderFrame, into: output)
                        image = try XCTUnwrap(context.createCGImage(CIImage(cvPixelBuffer: output),
                                                                    from: CGRect(origin: .zero, size: frame.geometry.frameSize)))
                    } else if let previewLongSide {
                        image = try XCTUnwrap(renderer.previewImage(from: input, profile: profile,
                                                                    customFrame: frame.renderFrame,
                                                                    maxLongSide: previewLongSide))
                    } else {
                        let screenshot = try XCTUnwrap(renderer.screenshot(from: input, profile: profile,
                                                                           customFrame: frame.renderFrame))
                        image = try XCTUnwrap(screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil))
                    }
                    let scale = previewLongSide.map { min(1, $0 / max(frame.geometry.frameSize.width,
                                                                      frame.geometry.frameSize.height)) } ?? 1
                    let screen = frame.geometry.screenRect.applying(CGAffineTransform(scaleX: scale, y: scale))
                    let radius = profile.scaledCornerRadius(for: frame.geometry.screenRect.size) * scale
                    let data = pixels(image)
                    let audit = edgeAudit(data, width: image.width, height: image.height,
                                          screen: screen, radius: radius, margin: 10 * scale)
                    let kind = movie ? "movie" : previewLongSide.map { "preview-\(Int($0))" } ?? "screenshot"
                    let sourceLabel = capturedPortraitSize == nil ? "" : "-cross-model"
                    let label = "\(profile.id) \(landscape ? "landscape" : "portrait") \(kind)\(sourceLabel)"
                    XCTAssertGreaterThan(audit.samples, 100, label)
                    XCTAssertEqual(audit.leaks, 0,
                                   "\(label): \(audit.leaks)/\(audit.samples) seam pixels, minimum alpha \(audit.minimumAlpha); first \(audit.examples)")
                    for (x, y) in [(0, 0), (image.width - 1, 0), (0, image.height - 1),
                                   (image.width - 1, image.height - 1)] {
                        XCTAssertEqual(data[(y * image.width + x) * 4 + 3], 0,
                                       "\(label): sealing the inner screen must retain transparent outer corners")
                    }
                    if audit.leaks > 0 || (profile.id == "iphone-17-pro" && !landscape && previewLongSide == nil),
                       let folder = ProcessInfo.processInfo.environment["BEZELCAST_TEST_ARTIFACTS"] {
                        try writeCorner(image, screen: screen, radius: radius,
                                        to: URL(fileURLWithPath: folder, isDirectory: true)
                                            .appendingPathComponent("edge-\(profile.id)-\(landscape ? "landscape" : "portrait")-\(kind)\(sourceLabel).png"))
                    }
                }
            }
        }
    }

    private struct EdgeAudit {
        var samples = 0
        var leaks = 0
        var minimumAlpha: UInt8 = 255
        var examples: [String] = []
    }

    private func edgeAudit(_ pixels: [UInt8], width: Int, height: Int,
                           screen: CGRect, radius: CGFloat, margin: CGFloat) -> EdgeAudit {
        var result = EdgeAudit()
        forEachEdgePixel(width: width, height: height, screen: screen, radius: radius, margin: margin) { x, y in
            let alpha = pixels[(y * width + x) * 4 + 3]
            result.samples += 1
            result.minimumAlpha = min(result.minimumAlpha, alpha)
            if alpha < 254 {
                result.leaks += 1
                if result.examples.count < 4 { result.examples.append("(\(x),\(y))=\(alpha)") }
            }
        }
        return result
    }

    private func forEachEdgePixel(width: Int, height: Int, screen: CGRect, radius: CGFloat, margin: CGFloat,
                                  body: (Int, Int) -> Void) {
        let outside = screen.insetBy(dx: -margin, dy: -margin)
        let inside = screen.insetBy(dx: margin, dy: margin)
        for y in max(0, Int(floor(outside.minY)))..<min(height, Int(ceil(outside.maxY))) {
            guard let outer = span(outside, radius: radius + margin, y: CGFloat(y) + 0.5) else { continue }
            let inner = span(inside, radius: max(0, radius - margin), y: CGFloat(y) + 0.5)
            let first = max(0, Int(ceil(outer.lowerBound - 0.5)))
            let last = min(width - 1, Int(floor(outer.upperBound - 0.5)))
            guard first <= last else { continue }
            let ranges: [ClosedRange<Int>]
            if let inner {
                let leftEnd = min(last, Int(ceil(inner.lowerBound - 0.5)) - 1)
                let rightStart = max(first, Int(floor(inner.upperBound - 0.5)) + 1)
                ranges = (first <= leftEnd ? [first...leftEnd] : []) + (rightStart <= last ? [rightStart...last] : [])
            } else {
                ranges = [first...last]
            }
            for range in ranges {
                for x in range { body(x, y) }
            }
        }
    }

    private func span(_ rect: CGRect, radius: CGFloat, y: CGFloat) -> ClosedRange<CGFloat>? {
        guard y >= rect.minY, y <= rect.maxY else { return nil }
        let r = min(radius, min(rect.width, rect.height) / 2)
        let dy = max(0, max(rect.minY + r - y, y - (rect.maxY - r)))
        let inset = r > 0 ? r - sqrt(max(0, r * r - dy * dy)) : 0
        return (rect.minX + inset)...(rect.maxX - inset)
    }

    private func whiteBuffer(_ size: CGSize) throws -> CVPixelBuffer {
        let output = try buffer(size)
        context.render(CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size)), to: output)
        return output
    }

    private func buffer(_ size: CGSize) throws -> CVPixelBuffer {
        var output: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                         kCVPixelFormatType_32BGRA,
                                         [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &output)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(output)
        context.render(CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: size)), to: buffer)
        return buffer
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
        result.withUnsafeMutableBytes { storage in
            let drawing = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            drawing.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return result
    }

    private func writeCorner(_ image: CGImage, screen: CGRect, radius: CGFloat, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let side = ceil(max(screen.minX, screen.minY) + radius + 18)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: min(side, CGFloat(image.width)),
                                                         height: min(side, CGFloat(image.height)))))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, crop, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try writeMagentaCorner(crop, to: url.deletingPathExtension().appendingPathExtension("magenta.png"))
        if let folder = ProcessInfo.processInfo.environment["BEZELCAST_EDGE_BASELINE_DIRECTORY"] {
            let baseline = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(url.lastPathComponent)
            if let source = CGImageSourceCreateWithURL(baseline as CFURL, nil),
               let original = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                try writeMagentaCorner(original, to: baseline.deletingPathExtension().appendingPathExtension("magenta.png"))
            }
        }
    }

    private func writeMagentaCorner(_ image: CGImage, to url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width * 3, height: image.height * 3,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bounds = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(bounds)
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
