import AppKit
import CoreImage
import CoreVideo
import XCTest
@testable import BezelCast

final class BezelLibraryTests: XCTestCase {
    func testPickerExcludesDifferentDeviceFamiliesAndScreenShapes() throws {
        let modern = try option("iphone-18-pro")
        let choices = BezelLibrary.compatible(with: modern.profile)
        XCTAssertTrue(choices.contains { $0.profileID == "iphone-air" })
        XCTAssertFalse(choices.contains { $0.profileID == "iphone-se" })
        XCTAssertFalse(choices.contains { $0.profile.family == .iPad })

        let landscape = modern.profile.oriented(matching: CGSize(width: 2622, height: 1206))
        XCTAssertEqual(Set(choices.map(\.id)), Set(BezelLibrary.compatible(with: landscape).map(\.id)))

        let se = try option("iphone-se")
        XCTAssertTrue(BezelLibrary.compatible(with: se.profile).allSatisfy { $0.profileID == "iphone-se" })
        let tablet = try option("ipad-pro-13")
        XCTAssertTrue(BezelLibrary.compatible(with: tablet.profile).allSatisfy { $0.profile.family == .iPad })
    }

    func testGeneratedFramesHaveTransparentScreensAndOpaqueSurrounds() throws {
        for id in ["iphone-18-pro", "iphone-17e", "iphone-se", "ipad-pro-13"] {
            try autoreleasepool {
                let selection = try option(id)
                let frame = try XCTUnwrap(BezelLibrary.frame(for: selection, orientedTo: selection.profile))
                let pixels = try Pixels(frame.image)
                let geometry = frame.geometry
                let screen = geometry.screenRect

                XCTAssertEqual(screen.size, selection.profile.screenSize, id)
                XCTAssertEqual(pixels.width, Int(geometry.frameSize.width), id)
                XCTAssertEqual(pixels.height, Int(geometry.frameSize.height), id)
                XCTAssertTrue(CGRect(origin: .zero, size: geometry.frameSize).contains(screen), id)
                XCTAssertEqual(pixels.at(screen.midX, screen.midY).alpha, 0, accuracy: 0.01, id)
                XCTAssertEqual(pixels.at(0, 0).alpha, 0, accuracy: 0.01, id)
                XCTAssertEqual(pixels.at(screen.midX, screen.minY / 2).alpha, 1, accuracy: 0.01, id)
                XCTAssertEqual(pixels.at(screen.minX / 2, screen.midY).alpha, 1, accuracy: 0.01, id)
                XCTAssertEqual(pixels.at(screen.midX, screen.maxY + (geometry.frameSize.height - screen.maxY) / 2).alpha,
                               1, accuracy: 0.01, id)
            }
        }
    }

    func testRoundedScreenAndCameraRemainVisibleInArtwork() throws {
        let selection = try option("iphone-18-pro")
        let frame = try XCTUnwrap(BezelLibrary.frame(for: selection, orientedTo: selection.profile))
        let pixels = try Pixels(frame.image)
        let screen = frame.geometry.screenRect
        // Sample the ring between the rounded body and rounded screen, not the
        // transparent area beyond both curves at the canvas corner.
        XCTAssertEqual(pixels.at(screen.minX + 40, screen.minY + 40).alpha, 1, accuracy: 0.01)
        XCTAssertEqual(pixels.at(screen.midX, screen.minY + 74).alpha, 1, accuracy: 0.01)
        XCTAssertEqual(pixels.at(screen.midX, screen.minY + 180).alpha, 0, accuracy: 0.01)
        XCTAssertEqual(pixels.at(screen.midX, screen.maxY - 74).alpha, 0, accuracy: 0.01)
    }

    func testLandscapeRotationKeepsArtworkAndScreenGeometryTogether() throws {
        let selection = try option("iphone-18-pro")
        let portrait = try XCTUnwrap(BezelLibrary.frame(for: selection, orientedTo: selection.profile))
        let landscapeProfile = selection.profile.oriented(matching: CGSize(width: 2622, height: 1206))
        let landscape = try XCTUnwrap(BezelLibrary.frame(for: selection, orientedTo: landscapeProfile))
        XCTAssertEqual(landscape.geometry, portrait.geometry.rotated(clockwise: true))
        let pixels = try Pixels(landscape.image)
        let screen = landscape.geometry.screenRect
        XCTAssertEqual(pixels.width, Int(portrait.geometry.frameSize.height))
        XCTAssertEqual(pixels.height, Int(portrait.geometry.frameSize.width))
        XCTAssertEqual(pixels.at(screen.midX, screen.midY).alpha, 0, accuracy: 0.01)

        // A clockwise rotation moves the camera from the top to the right.
        XCTAssertEqual(pixels.at(screen.maxX - 74, screen.midY).alpha, 1, accuracy: 0.01)
        XCTAssertEqual(pixels.at(screen.minX + 74, screen.midY).alpha, 0, accuracy: 0.01)
        let returnedPortrait = try XCTUnwrap(landscape.oriented(to: selection.profile))
        XCTAssertEqual(returnedPortrait.geometry, portrait.geometry)
        XCTAssertNil(portrait.oriented(to: try option("iphone-se").profile))
    }

    func testThumbnailsProvideFilledScreensWithoutAllocatingFullSizeArtwork() throws {
        for id in ["iphone-18-pro", "iphone-air", "iphone-se", "ipad-pro-13"] {
            let selection = try option(id)
            let thumbnail = try XCTUnwrap(selection.thumbnail)
            let pixels = try Pixels(thumbnail)
            XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), 161, id)
            XCTAssertEqual(thumbnail.size.height, 80, id)
            XCTAssertEqual(pixels.at(CGFloat(pixels.width) / 2, CGFloat(pixels.height) / 2).alpha,
                           1, accuracy: 0.01, id)
            XCTAssertEqual(pixels.at(0, 0).alpha, 0, accuracy: 0.01, id)
        }
    }

    func testDifferentFinishesProduceDifferentVisibleArtwork() throws {
        let black = try option("iphone-18-pro", finish: .black)
        let silver = try option("iphone-18-pro", finish: .silver)
        let first = try XCTUnwrap(BezelLibrary.frame(for: black, orientedTo: black.profile))
        let second = try XCTUnwrap(BezelLibrary.frame(for: silver, orientedTo: silver.profile))
        let dark = try Pixels(first.image).at(first.geometry.frameSize.width / 2, 5)
        let light = try Pixels(second.image).at(second.geometry.frameSize.width / 2, 5)
        XCTAssertGreaterThan(light.red - dark.red, 0.2)
        XCTAssertGreaterThan(light.green - dark.green, 0.2)
        XCTAssertEqual(first.geometry, second.geometry)
    }

    func testHomeButtonIPadFrontsFollowTheirGenerationAndFinish() throws {
        for (id, finish, expectedLight) in [("ipad-10-2-7-8", BezelFinish.silver, true),
                                            ("ipad-10-2-7-8", .spaceGray, false),
                                            ("ipad-10-2", .silver, false)] {
            let selection = try option(id, finish: finish)
            let frame = try XCTUnwrap(BezelLibrary.frame(for: selection, orientedTo: selection.profile))
            let pixel = try Pixels(frame.image).at(frame.geometry.frameSize.width / 2,
                                                   frame.geometry.screenRect.minY / 2)
            XCTAssertEqual(pixel.alpha, 1, accuracy: 0.01)
            if expectedLight { XCTAssertGreaterThan(pixel.red, 0.85, id) }
            else { XCTAssertLessThan(pixel.red, 0.1, id) }
        }
    }

    func testScreenshotKeepsVideoQuadrantsAlignedInBothOrientations() throws {
        let selection = try option("iphone-18-pro")
        let renderer = BezelRenderer(ciContext: CIContext())
        for landscape in [false, true] {
            try autoreleasepool {
                let profile = selection.profile.oriented(matching: landscape
                    ? CGSize(width: 2622, height: 1206) : selection.profile.screenSize)
                let frame = try XCTUnwrap(BezelLibrary.frame(for: selection, orientedTo: profile))
                let buffer = try quadrantBuffer(size: profile.screenSize)
                let screenshot = try XCTUnwrap(renderer.screenshot(from: buffer, profile: profile,
                                                                   customFrame: frame.renderFrame))
                let pixels = try Pixels(screenshot)
                let screen = frame.geometry.screenRect
                XCTAssertEqual(pixels.width, Int(frame.geometry.frameSize.width))
                XCTAssertEqual(pixels.height, Int(frame.geometry.frameSize.height))
                assertColor(pixels.at(screen.minX + screen.width * 0.25, screen.minY + screen.height * 0.25),
                            red: 1, green: 0, blue: 0)
                assertColor(pixels.at(screen.minX + screen.width * 0.75, screen.minY + screen.height * 0.25),
                            red: 0, green: 1, blue: 0)
                assertColor(pixels.at(screen.minX + screen.width * 0.25, screen.minY + screen.height * 0.75),
                            red: 0, green: 0, blue: 1)
                assertColor(pixels.at(screen.minX + screen.width * 0.75, screen.minY + screen.height * 0.75),
                            red: 1, green: 1, blue: 0)
                XCTAssertEqual(pixels.at(0, 0).alpha, 0, accuracy: 0.01)
            }
        }
    }

    private func option(_ profileID: String, finish: BezelFinish? = nil) throws -> BezelOption {
        if let finish {
            return try XCTUnwrap(BezelLibrary.option(id: "\(profileID)/\(finish.rawValue)"))
        }
        let profile = try XCTUnwrap(DeviceProfile.catalog.first { $0.id == profileID })
        return try XCTUnwrap(BezelLibrary.automatic(for: profile))
    }

    private func assertColor(_ color: NSColor, red: CGFloat, green: CGFloat, blue: CGFloat,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(color.redComponent, red, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(color.greenComponent, green, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(color.blueComponent, blue, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01, file: file, line: line)
    }

    private func quadrantBuffer(size: CGSize) throws -> CVPixelBuffer {
        let width = Int(size.width), height = Int(size.height)
        var optionalBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                          nil, &optionalBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(optionalBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let data = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * stride + x * 4
                let left = x < width / 2, top = y < height / 2
                data[index] = !top && left ? 255 : 0
                data[index + 1] = !left ? 255 : 0
                data[index + 2] = (top && left) || (!top && !left) ? 255 : 0
                data[index + 3] = 255
            }
        }
        return buffer
    }

    private struct Pixels {
        private let bitmap: NSBitmapImageRep
        var width: Int { bitmap.pixelsWide }
        var height: Int { bitmap.pixelsHigh }

        init(_ image: NSImage) throws {
            bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil,
                                                                          context: nil, hints: nil)))
        }

        func at(_ x: CGFloat, _ y: CGFloat) -> NSColor {
            bitmap.colorAt(x: Int(x), y: Int(y))!.usingColorSpace(.deviceRGB)!
        }
    }
}

private extension NSColor {
    var alpha: CGFloat { alphaComponent }
    var red: CGFloat { redComponent }
    var green: CGFloat { greenComponent }
}
