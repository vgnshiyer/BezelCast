import AppKit
import CoreImage
import CoreText
import CoreVideo
import XCTest
@testable import BezelCast

final class CapturedScreenPreservationTests: XCTestCase {
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    ])

    func testCapturedClockNetworkAndWallpaperPassThroughEveryOutput() throws {
        let profile = try phone()
        let input = try capturedScreen(profile.screenSize)
        let source = try image(input)
        let renderer = BezelRenderer(ciContext: context)
        let screenshot = try cgImage(XCTUnwrap(renderer.screenshot(from: input, profile: profile, customFrame: nil)))
        let preview = try XCTUnwrap(renderer.previewImage(from: input, profile: profile, customFrame: nil,
                                                          maxLongSide: profile.screenSize.height))
        let video = try buffer(profile.screenSize)
        renderer.composite(video: input, profile: profile, customFrame: nil, into: video)
        for (name, output) in [("screenshot", screenshot), ("preview", preview), ("video", try image(video))] {
            XCTAssertEqual(output.width, source.width)
            XCTAssertEqual(output.height, source.height)
            assertRegionsMatch(source, output, regions: visibleScreenRegions(profile), label: name)
        }
    }

    func testBlueCanvasCannotLeakIntoCapturedStatusPixelsInsidePhoneBezel() throws {
        let profile = try phone()
        let input = try capturedScreen(profile.screenSize)
        let option = try XCTUnwrap(BezelLibrary.automatic(for: profile))
        let frame = try XCTUnwrap(BezelLibrary.frame(for: option, orientedTo: profile))
        let renderer = BezelRenderer(ciContext: context)
        let original = try cgImage(XCTUnwrap(renderer.screenshot(from: input, profile: profile,
                                                                 customFrame: frame.renderFrame)))
        let margin: CGFloat = 100
        let canvasSize = CGSize(width: frame.geometry.frameSize.width + margin * 2,
                                height: frame.geometry.frameSize.height + margin * 2)
        let presentation = CapturePresentation(
            background: CaptureBackground(id: "preservation-blue", name: "Blue",
                                           content: .solid(BackgroundColor(red: 0, green: 0.65, blue: 1))),
            padding: margin / canvasSize.width, shadow: false, fixedCanvasSize: canvasSize)
        let fitted = presentation.deviceRect(for: frame.geometry.frameSize)
        XCTAssertEqual(fitted.width, frame.geometry.frameSize.width, accuracy: 0.0001)
        XCTAssertEqual(fitted.height, frame.geometry.frameSize.height, accuracy: 0.0001)
        let screenshot = try cgImage(XCTUnwrap(renderer.screenshot(from: input, profile: profile,
                                                                  customFrame: frame.renderFrame,
                                                                  presentation: presentation)))
        let preview = try XCTUnwrap(renderer.previewImage(from: input, profile: profile,
                                                          customFrame: frame.renderFrame,
                                                          presentation: presentation,
                                                          maxLongSide: canvasSize.height))
        let video = try buffer(canvasSize)
        renderer.composite(video: input, profile: profile, customFrame: frame.renderFrame,
                           presentation: presentation, into: video)
        let screen = frame.geometry.screenRect
        let regions = visibleScreenRegions(profile).map { $0.offsetBy(dx: screen.minX, dy: screen.minY) }
        for (name, output) in [("screenshot", screenshot), ("preview", preview), ("video", try image(video))] {
            XCTAssertEqual(output.width, Int(canvasSize.width))
            XCTAssertEqual(output.height, Int(canvasSize.height))
            // Compare with the original framed capture, so the bezel's opaque
            // hardware cutout remains explicitly part of the expected image.
            assertRegionsMatch(original, output, regions: regions,
                               outputOffset: CGPoint(x: margin, y: margin), label: "blue canvas \(name)")
            let corner = pixels(output)
            let offset = (10 * output.width + 10) * 4
            XCTAssertLessThan(corner[offset], 2)
            XCTAssertGreaterThan(corner[offset + 1], 150)
            XCTAssertGreaterThan(corner[offset + 2], 250)
            XCTAssertEqual(corner[offset + 3], 255)
        }
    }

    private func phone() throws -> DeviceProfile {
        try XCTUnwrap(DeviceProfile.catalog.first { $0.id == "iphone-17-pro" })
    }

    private func visibleScreenRegions(_ profile: DeviceProfile) -> [CGRect] {
        // The top region includes both original icon groups, wallpaper between
        // them, and the rows formerly sampled to construct replacement patches.
        // It stays inside the phone's rounded display corners.
        [CGRect(x: 90, y: 35, width: profile.screenSize.width - 180, height: 175),
         CGRect(x: 200, y: 240, width: profile.screenSize.width - 400, height: 240)]
    }

    private func capturedScreen(_ size: CGSize) throws -> CVPixelBuffer {
        let wallpaper = try buffer(size)
        CVPixelBufferLockBaseAddress(wallpaper, [])
        let storage = try XCTUnwrap(CVPixelBufferGetBaseAddress(wallpaper)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(wallpaper)
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                let offset = y * stride + x * 4
                // Vary both axes so extending neighboring rows, adding a solid
                // blue patch, or shifting screen content cannot pass unnoticed.
                storage[offset] = UInt8(20 + (x / 16 * 5 + y / 9 * 9) % 130)
                storage[offset + 1] = UInt8(30 + (x / 12 * 11 + y / 10 * 5) % 120)
                storage[offset + 2] = UInt8(20 + (x / 8 * 7 + y / 8 * 13) % 160)
                storage[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(wallpaper, [])

        // These glyphs are part of the captured input. The renderer must pass
        // them through; it has no clock, battery, or network UI to draw itself.
        let icons = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: 120,
                                            bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 45, nil)!
        let clock = NSAttributedString(string: "11:27", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
        icons.textPosition = CGPoint(x: 105, y: 42)
        CTLineDraw(CTLineCreateWithAttributedString(clock), icons)
        icons.setFillColor(CGColor(gray: 1, alpha: 1))
        for bar in 0..<4 {
            icons.fill(CGRect(x: size.width - 350 + CGFloat(bar) * 14, y: 45,
                              width: 10, height: CGFloat(12 + bar * 6)))
        }
        icons.setStrokeColor(CGColor(gray: 1, alpha: 1))
        icons.setLineWidth(4)
        icons.strokeEllipse(in: CGRect(x: size.width - 278, y: 46, width: 34, height: 28))
        icons.stroke(CGRect(x: size.width - 215, y: 44, width: 66, height: 30))
        icons.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.1, alpha: 1))
        icons.fill(CGRect(x: size.width - 210, y: 49, width: 16, height: 20))
        let capturedIcons = CIImage(cgImage: try XCTUnwrap(icons.makeImage()))
            .transformed(by: CGAffineTransform(translationX: 0, y: size.height - 120))
        let output = try buffer(size)
        context.render(capturedIcons.composited(over: CIImage(cvPixelBuffer: wallpaper)), to: output)
        return output
    }

    private func buffer(_ size: CGSize) throws -> CVPixelBuffer {
        var output: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                         kCVPixelFormatType_32BGRA,
                                         [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
                                         &output)
        XCTAssertEqual(result, kCVReturnSuccess)
        return try XCTUnwrap(output)
    }

    private func image(_ buffer: CVPixelBuffer) throws -> CGImage {
        try XCTUnwrap(context.createCGImage(CIImage(cvPixelBuffer: buffer),
                                            from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer),
                                                         height: CVPixelBufferGetHeight(buffer))))
    }

    private func cgImage(_ image: NSImage) throws -> CGImage {
        try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
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

    private func assertRegionsMatch(_ expected: CGImage, _ actual: CGImage, regions: [CGRect],
                                    outputOffset: CGPoint = .zero, label: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let expectedPixels = pixels(expected), actualPixels = pixels(actual)
        var changed = 0, maximumError = 0, maximumAlphaError = 0
        var examples: [String] = []
        for region in regions {
            for y in Int(region.minY)..<Int(region.maxY) {
                for x in Int(region.minX)..<Int(region.maxX) {
                    let expectedOffset = (y * expected.width + x) * 4
                    let actualOffset = ((y + Int(outputOffset.y)) * actual.width + x + Int(outputOffset.x)) * 4
                    var error = 0
                    for channel in 0..<4 {
                        error = max(error, abs(Int(expectedPixels[expectedOffset + channel])
                                               - Int(actualPixels[actualOffset + channel])))
                    }
                    maximumAlphaError = max(maximumAlphaError, abs(Int(expectedPixels[expectedOffset + 3])
                                                                   - Int(actualPixels[actualOffset + 3])))
                    guard error > 0 else { continue }
                    changed += 1
                    maximumError = max(maximumError, error)
                    if examples.count < 5 { examples.append("(\(x),\(y)): \(error)") }
                }
            }
        }
        let summary = "\(label): \(changed) differing pixels; maximum RGBA error \(maximumError); first differences \(examples)"
        // Permit only 8-bit rounding between CI and bitmap output; replacement
        // glyphs, donor-row smearing, and leaked blue blocks exceed this bound.
        XCTAssertLessThanOrEqual(maximumError, 1, summary, file: file, line: line)
        XCTAssertEqual(maximumAlphaError, 0, summary, file: file, line: line)
    }
}
