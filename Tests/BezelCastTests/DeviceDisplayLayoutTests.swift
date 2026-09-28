import AppKit
import CoreImage
import CoreVideo
import XCTest
@testable import BezelCast

final class DeviceDisplayLayoutTests: XCTestCase {
    func testSwitchingBetweenMiniAndProModelsKeepsTheSameVisibleHeight() throws {
        let available = CGSize(width: 500, height: 724)
        for id in ["iphone-13-mini", "iphone-17-pro", "iphone-18-pro-max"] {
            try autoreleasepool {
                let profile = try profile(id)
                let option = try XCTUnwrap(BezelLibrary.automatic(for: profile))
                let frame = try XCTUnwrap(BezelLibrary.frame(for: option, orientedTo: profile))
                let preview = DeviceDisplayLayout.previewSize(for: profile,
                                                            customFrame: frame,
                                                            fitting: available)
                XCTAssertEqual(preview.height, available.height, accuracy: 0.001, id)
                assertFits(preview, source: frame.geometry.frameSize, inside: available)
            }
        }
    }

    func testEveryUnframedDeviceFitsWithoutDistortionInEitherOrientation() {
        for profile in DeviceProfile.catalog {
            for landscape in [false, true] {
                let oriented = profile.oriented(matching: landscape
                    ? CGSize(width: 3000, height: 1000) : profile.screenSize)
                for available in [CGSize(width: 328, height: 264),
                                  CGSize(width: 388, height: 724),
                                  CGSize(width: 900, height: 500)] {
                    let preview = DeviceDisplayLayout.previewSize(for: oriented,
                                                                customFrame: nil,
                                                                fitting: available)
                    assertFits(preview, source: oriented.screenSize, inside: available)
                }
            }
        }
    }

    func testManuallyEnlargingTheWindowAlsoEnlargesThePreview() throws {
        let profile = try profile("iphone-13-mini")
        let small = DeviceDisplayLayout.previewSize(for: profile, customFrame: nil,
                                                   fitting: CGSize(width: 400, height: 700))
        let large = DeviceDisplayLayout.previewSize(for: profile, customFrame: nil,
                                                   fitting: CGSize(width: 800, height: 1400))
        XCTAssertEqual(large.width, small.width * 2, accuracy: 0.001)
        XCTAssertEqual(large.height, small.height * 2, accuracy: 0.001)
    }

    func testImportedBezelFitsItsWholeCanvasIncludingAfterRotation() throws {
        let profile = try profile("iphone-18-pro")
        let frame = try importedFrame(for: profile)
        let available = CGSize(width: 388, height: 724)
        for landscape in [false, true] {
            let oriented = profile.oriented(matching: landscape
                    ? CGSize(width: 3000, height: 1000) : profile.screenSize)
            let orientedFrame = try XCTUnwrap(frame.oriented(to: oriented))
            let preview = DeviceDisplayLayout.previewSize(for: oriented,
                                                        customFrame: orientedFrame,
                                                        fitting: available)
            assertFits(preview, source: orientedFrame.geometry.frameSize, inside: available)
            // The wider imported artwork uses the available width, leaving
            // space below instead of clipping its rails to the screen shape.
            XCTAssertEqual(preview.width, available.width, accuracy: 0.001)
            XCTAssertLessThan(preview.height, available.height)
        }
    }

    func testEmptyOrInvalidLayoutProposalsProduceNoPreview() throws {
        let profile = try profile("iphone-18-pro")
        for available in [CGSize.zero,
                          CGSize(width: -1, height: 724),
                          CGSize(width: 388, height: 0),
                          CGSize(width: CGFloat.infinity, height: 724),
                          CGSize(width: 388, height: CGFloat.nan)] {
            XCTAssertEqual(DeviceDisplayLayout.previewSize(for: profile, customFrame: nil,
                                                          fitting: available), .zero)
        }
    }

    func testScreenshotResolutionRemainsIndependentOfPreviewSize() throws {
        let profile = try profile("iphone-18-pro")
        let frame = try importedFrame(for: profile)
        let renderer = BezelRenderer(ciContext: CIContext())
        var optionalBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 8, kCVPixelFormatType_32BGRA,
                                          nil, &optionalBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(optionalBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        memset(bytes, 255, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        for customFrame: CustomFrame? in [nil, frame] {
            for available in [CGSize(width: 328, height: 264), CGSize(width: 800, height: 1400)] {
                let preview = DeviceDisplayLayout.previewSize(for: profile, customFrame: customFrame,
                                                            fitting: available)
                let screenshot = try XCTUnwrap(renderer.screenshot(from: buffer, profile: profile,
                                                                   customFrame: customFrame?.renderFrame))
                let image = try XCTUnwrap(screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let nativeSize = customFrame?.geometry.frameSize ?? profile.screenSize
                XCTAssertEqual(image.width, Int(nativeSize.width))
                XCTAssertEqual(image.height, Int(nativeSize.height))
                XCTAssertNotEqual(CGSize(width: image.width, height: image.height), preview)
            }
        }
    }

    private func profile(_ id: String) throws -> DeviceProfile {
        try XCTUnwrap(DeviceProfile.catalog.first { $0.id == id })
    }

    private func importedFrame(for profile: DeviceProfile) throws -> CustomFrame {
        let geometry = FrameGeometry(frameSize: CGSize(width: 120, height: 160),
                                     screenRect: CGRect(x: 30, y: 30, width: 46, height: 100))
        let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 160,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: geometry.frameSize))
        context.clear(geometry.screenRect)
        let image = try XCTUnwrap(context.makeImage())
        return try XCTUnwrap(CustomFrame.make(name: "Wide imported frame",
                                             image: NSImage(cgImage: image, size: geometry.frameSize),
                                             cgImage: image, geometry: geometry, profile: profile))
    }

    private func assertFits(_ preview: CGSize, source: CGSize, inside available: CGSize,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(preview.width, 0, file: file, line: line)
        XCTAssertGreaterThan(preview.height, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(preview.width, available.width + 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(preview.height, available.height + 0.001, file: file, line: line)
        XCTAssertEqual(preview.width / preview.height, source.width / source.height,
                       accuracy: 0.0001, file: file, line: line)
        XCTAssertTrue(abs(preview.width - available.width) < 0.001
                      || abs(preview.height - available.height) < 0.001,
                      "Preview should use the available space", file: file, line: line)
    }
}
