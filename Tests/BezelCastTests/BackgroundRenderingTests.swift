import AppKit
import CoreImage
import CoreVideo
import XCTest
@testable import BezelCast

final class BackgroundRenderingTests: XCTestCase {
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    ])
    private let profile = DeviceProfile(id: "background-test", displayName: "Test", family: .iPhone,
                                        screenSize: CGSize(width: 40, height: 80), displayScale: 1,
                                        frameSize: CGSize(width: 40, height: 80), screenOffset: .zero,
                                        screenCornerRadius: 8, displayCutout: .none)

    func testNonePreservesNativeScreenshotAndTransparency() throws {
        let renderer = BezelRenderer(ciContext: context)
        let buffer = try blueBuffer()
        let original = try XCTUnwrap(renderer.screenshot(from: buffer, profile: profile, customFrame: nil))
        let explicitNone = try XCTUnwrap(renderer.screenshot(from: buffer, profile: profile, customFrame: nil,
                                                            presentation: CapturePresentation(background: .none,
                                                                                              canvas: .square,
                                                                                              padding: 0.3)))
        let first = try cgImage(original)
        let second = try cgImage(explicitNone)
        XCTAssertEqual(original.size, profile.screenSize)
        XCTAssertEqual(first.width, 40)
        XCTAssertEqual(first.height, 80)
        XCTAssertEqual(pixels(first), pixels(second))
        XCTAssertEqual(pixel(first, x: 0, y: 0)[3], 0)
        XCTAssertEqual(pixel(first, x: 20, y: 40), [0, 0, 255, 255])
    }

    func testSolidBackgroundUsesSharedPaddingAndPreviewGeometry() throws {
        let presentation = CapturePresentation(background: solid("red", 1, 0, 0), padding: 0.2,
                                               shadow: false, fixedCanvasSize: CGSize(width: 200, height: 200))
        let renderer = BezelRenderer(ciContext: context)
        let buffer = try blueBuffer()
        let screenshot = try cgImage(XCTUnwrap(renderer.screenshot(from: buffer, profile: profile,
                                                                  customFrame: nil, presentation: presentation)))
        let preview = try XCTUnwrap(renderer.previewImage(from: buffer, profile: profile, customFrame: nil,
                                                          presentation: presentation))
        XCTAssertEqual(presentation.deviceRect(for: profile.screenSize), CGRect(x: 70, y: 40, width: 60, height: 120))
        XCTAssertEqual(pixels(screenshot), pixels(preview))
        XCTAssertEqual(pixel(screenshot, x: 20, y: 100), [255, 0, 0, 255])
        XCTAssertEqual(pixel(screenshot, x: 100, y: 100), [0, 0, 255, 255])
        XCTAssertEqual(pixel(screenshot, x: 100, y: 35), [255, 0, 0, 255])
        XCTAssertEqual(pixel(screenshot, x: 100, y: 45), [0, 0, 255, 255])
    }

    func testGradientReachesOppositeCanvasCorners() throws {
        let background = CaptureBackground(id: "gradient", name: "Gradient", content: .gradient(
            BackgroundColor(red: 1, green: 0, blue: 0), BackgroundColor(red: 0, green: 1, blue: 0)))
        let image = try render(CapturePresentation(background: background, shadow: false,
                                                    fixedCanvasSize: CGSize(width: 200, height: 200)))
        // CGImage bitmap rows start at the top of the exported image.
        let topLeft = pixel(image, x: 2, y: 2)
        let bottomRight = pixel(image, x: 197, y: 197)
        XCTAssertGreaterThan(topLeft[0], 245)
        XCTAssertLessThan(topLeft[1], 35)
        XCTAssertGreaterThan(bottomRight[1], 245)
        XCTAssertLessThan(bottomRight[0], 35)
        XCTAssertEqual(topLeft[3], 255)
        XCTAssertEqual(bottomRight[3], 255)
    }

    func testWallpaperFillsCanvasWithCenteredCrop() throws {
        let drawing = try XCTUnwrap(CGContext(data: nil, width: 300, height: 100, bitsPerComponent: 8,
                                               bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        drawing.setFillColorSpace(CGColorSpace(name: CGColorSpace.sRGB)!)
        let stripes: [[CGFloat]] = [[1, 0, 0, 1], [0, 1, 0, 1], [0, 0, 1, 1]]
        for (index, components) in stripes.enumerated() {
            drawing.setFillColor(components)
            drawing.fill(CGRect(x: index * 100, y: 0, width: 100, height: 100))
        }
        let wallpaper = try XCTUnwrap(drawing.makeImage())
        let background = CaptureBackground(id: "image", name: "Image", content: .image(wallpaper))
        let image = try render(CapturePresentation(background: background, shadow: false,
                                                    fixedCanvasSize: CGSize(width: 200, height: 200)))
        // A square center crop contains only the middle green third. Stretching
        // or fitting the image would expose red/blue or transparent outer areas.
        for point in [(5, 5), (194, 5), (5, 194), (194, 194)] {
            XCTAssertEqual(pixel(image, x: point.0, y: point.1), [0, 255, 0, 255])
        }
    }

    func testShadowStaysOutsideDeviceAndCanBeDisabled() throws {
        var presentation = CapturePresentation(background: solid("white", 1, 1, 1), padding: 0.2,
                                               shadow: false, fixedCanvasSize: CGSize(width: 200, height: 200))
        let plain = try render(presentation)
        presentation.shadow = true
        let shadowed = try render(presentation)
        XCTAssertEqual(pixel(plain, x: 68, y: 100), [255, 255, 255, 255])
        XCTAssertLessThan(pixel(shadowed, x: 68, y: 100)[0], 250)
        XCTAssertEqual(pixel(shadowed, x: 100, y: 100), [0, 0, 255, 255])
        XCTAssertEqual(pixel(shadowed, x: 5, y: 100), [255, 255, 255, 255])
        let defaultContextImage = try XCTUnwrap(BezelRenderer(ciContext: CIContext()).previewImage(
            from: blueBuffer(), profile: profile, customFrame: nil, presentation: presentation))
        XCTAssertEqual(pixel(defaultContextImage, x: 5, y: 100), [255, 255, 255, 255],
                       "The default production color pipeline must not tint distant background pixels")
    }

    func testVideoFillsActualOutputWhenDeviceAndRequestedCanvasRotate() throws {
        let renderer = BezelRenderer(ciContext: context)
        let output = try buffer(size: CGSize(width: 320, height: 180))
        let presentation = CapturePresentation(background: solid("red", 1, 0, 0), canvas: .portrait,
                                               shadow: false)
        let input = try blueBuffer()
        renderer.composite(video: input, profile: profile.oriented(matching: CGSize(width: 80, height: 40)),
                           customFrame: nil, presentation: presentation, into: output)
        let image = try XCTUnwrap(context.createCGImage(CIImage(cvPixelBuffer: output),
                                                       from: CGRect(x: 0, y: 0, width: 320, height: 180)))
        XCTAssertEqual(pixel(image, x: 2, y: 2), [255, 0, 0, 255])
        XCTAssertEqual(pixel(image, x: 317, y: 177), [255, 0, 0, 255])
        XCTAssertEqual(pixel(image, x: 160, y: 90), [0, 0, 255, 255])
    }

    func testScreenshotUsesFinalBackgroundDuringCrossfade() throws {
        let presentation = CapturePresentation(background: solid("red", 1, 0, 0), shadow: false,
                                               fixedCanvasSize: CGSize(width: 200, height: 200),
                                               previousBackground: solid("green", 0, 1, 0),
                                               transitionStartTime: ProcessInfo.processInfo.systemUptime + 1)
        let screenshot = try render(presentation)
        let preview = try XCTUnwrap(BezelRenderer(ciContext: context).previewImage(
            from: blueBuffer(), profile: profile, customFrame: nil, presentation: presentation))
        XCTAssertEqual(pixel(screenshot, x: 5, y: 5), [255, 0, 0, 255])
        XCTAssertEqual(pixel(preview, x: 5, y: 5), [0, 255, 0, 255])
    }

    private func solid(_ id: String, _ red: Double, _ green: Double, _ blue: Double) -> CaptureBackground {
        CaptureBackground(id: id, name: id, content: .solid(BackgroundColor(red: red, green: green, blue: blue)))
    }

    private func render(_ presentation: CapturePresentation) throws -> CGImage {
        try cgImage(XCTUnwrap(BezelRenderer(ciContext: context).screenshot(
            from: blueBuffer(), profile: profile, customFrame: nil, presentation: presentation)))
    }

    private func cgImage(_ image: NSImage) throws -> CGImage {
        try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    private func blueBuffer() throws -> CVPixelBuffer {
        let result = try buffer(size: profile.screenSize)
        context.render(CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(
            to: CGRect(origin: .zero, size: profile.screenSize)), to: result)
        return result
    }

    private func buffer(size: CGSize) throws -> CVPixelBuffer {
        var optional: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                          kCVPixelFormatType_32BGRA,
                                          [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
                                          &optional)
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(optional)
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
        context.render(CIImage(cgImage: image), toBitmap: &result, rowBytes: image.width * 4,
                       bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return result
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let bytes = pixels(image)
        let offset = (y * image.width + x) * 4
        return Array(bytes[offset..<offset + 4])
    }
}
