import AppKit
import CoreImage
import CoreVideo
import XCTest
@testable import BezelCast

final class DisplayCutoutTests: XCTestCase {
    func testEveryCatalogModelHasItsReleasedDisplayCutout() throws {
        let groups: [(DisplayCutout, [String])] = [
            (.wideNotch, ["iphone-12", "iphone-12-mini", "iphone-12-pro", "iphone-12-pro-max"]),
            (.notch, ["iphone-13", "iphone-13-mini", "iphone-13-pro", "iphone-13-pro-max",
                      "iphone-14", "iphone-14-plus", "iphone-16e", "iphone-17e"]),
            (.dynamicIsland, ["iphone-14-pro", "iphone-14-pro-max",
                              "iphone-15", "iphone-15-plus", "iphone-15-pro", "iphone-15-pro-max",
                              "iphone-16", "iphone-16-plus", "iphone-16-pro", "iphone-16-pro-max",
                              "iphone-17", "iphone-17-pro", "iphone-17-pro-max", "iphone-air"]),
            (.compactDynamicIsland, ["iphone-18-pro", "iphone-18-pro-max"]),
            (.none, ["iphone-se", "ipad-pro-13", "ipad-pro-12-9-air-13", "ipad-air-13",
                     "ipad-pro-12-9-home-button", "ipad-pro-11-m4", "ipad-pro-11",
                     "ipad-11-air-11", "ipad-air-11", "ipad-air-10-9-5", "ipad-air-10-9-4",
                     "ipad-mini-8-3", "ipad-mini-8-3-6", "ipad-10-2", "ipad-10-2-7-8",
                     "ipad-air-10-5-pro-10-5", "ipad-pro-10-5", "ipad-9-7-mini-retina",
                     "ipad-pro-9-7", "ipad-air-2", "ipad-mini-7-9"]),
        ]
        let expectedIDs = groups.flatMap { $0.1 }
        XCTAssertEqual(expectedIDs.count, Set(expectedIDs).count)
        XCTAssertEqual(Set(expectedIDs), Set(DeviceProfile.catalog.map(\.id)))

        for (expected, ids) in groups {
            for id in ids {
                let profile = try XCTUnwrap(DeviceProfile.catalog.first { $0.id == id })
                XCTAssertEqual(profile.displayCutout, expected, id)
                let landscape = profile.oriented(matching: CGSize(width: 3_000, height: 1_000))
                XCTAssertEqual(landscape.displayCutout, expected, "\(id) landscape")
                XCTAssertEqual(landscape.oriented(matching: profile.screenSize).displayCutout,
                               expected, "\(id) returned to portrait")
            }
        }
    }

    func testNotchesJoinTheTopRailAndRetainTheirGenerationWidths() throws {
        let models: [(String, CGFloat)] = [
            ("iphone-12", 230), ("iphone-12-mini", 230),
            ("iphone-12-pro", 230), ("iphone-12-pro-max", 230),
            ("iphone-13", 185), ("iphone-13-mini", 185),
            ("iphone-13-pro", 185), ("iphone-13-pro-max", 185),
            ("iphone-14", 185), ("iphone-14-plus", 185),
            ("iphone-16e", 185), ("iphone-17e", 185),
        ]
        for (id, shoulder) in models {
            try autoreleasepool {
                let selection = try option(id)
                let frame = try XCTUnwrap(BezelLibrary.frame(for: selection, orientedTo: selection.profile))
                let pixels = try Pixels(frame.image)
                let screen = frame.geometry.screenRect
                for offset in [-shoulder, 0, shoulder] {
                    for depth: CGFloat in [2, 30] {
                        XCTAssertEqual(pixels.at(screen.midX + offset, screen.minY + depth).alphaComponent,
                                       1, accuracy: 0.01, "\(id): attached notch at \(offset), \(depth)")
                    }
                }
                XCTAssertEqual(pixels.at(screen.midX, screen.minY + 130).alphaComponent,
                               0, accuracy: 0.01, id)
                // These screen positions fall inside the wide 12-series notch,
                // but outside the narrower 13-series and later notch.
                for offset: CGFloat in [-280, 280] {
                    XCTAssertEqual(pixels.at(screen.midX + offset, screen.minY + 45).alphaComponent,
                                   shoulder == 230 ? 1 : 0, accuracy: 0.01, id)
                }
            }
        }
    }

    func testIslandsFloatBelowTheRailAndOtherScreensHaveNoCutout() throws {
        for id in ["iphone-14-pro", "iphone-15", "iphone-16-pro", "iphone-17", "iphone-air",
                   "iphone-18-pro", "iphone-18-pro-max", "iphone-se", "ipad-pro-13", "ipad-10-2"] {
            try autoreleasepool {
                let selection = try option(id)
                let frame = try XCTUnwrap(BezelLibrary.frame(for: selection, orientedTo: selection.profile))
                let pixels = try Pixels(frame.image)
                let screen = frame.geometry.screenRect
                XCTAssertEqual(pixels.at(screen.midX, screen.minY + 10).alphaComponent,
                               0, accuracy: 0.01, "\(id): gap above camera")
                let hasIsland = selection.profile.displayCutout != .none
                XCTAssertEqual(pixels.at(screen.midX, screen.minY + 70).alphaComponent,
                               hasIsland ? 1 : 0, accuracy: 0.01, id)
                XCTAssertEqual(pixels.at(screen.midX + 185, screen.minY + 30).alphaComponent,
                               0, accuracy: 0.01, id)
            }
        }
    }

    func testPickerThumbnailsShowNotchesAndIslandsDistinctly() throws {
        for (id, shoulder): (String, CGFloat) in [("iphone-12", 230), ("iphone-13", 185),
                                                  ("iphone-14-plus", 185), ("iphone-16e", 185),
                                                  ("iphone-17e", 185)] {
            let selection = try option(id)
            let pixels = try Pixels(XCTUnwrap(selection.thumbnail))
            let geometry = BezelLibrary.geometry(for: selection.profile)
            let screen = geometry.screenRect
            let scale = 160 / geometry.frameSize.height
            for offset in [-shoulder, 0, shoulder] {
                let color = pixels.at((screen.midX + offset) * scale, (screen.minY + 30) * scale)
                XCTAssertLessThan(color.blueComponent, 0.055, "\(id): dark connected notch")
            }
        }
        for id in ["iphone-14-pro", "iphone-18-pro", "iphone-se", "ipad-pro-13"] {
            let selection = try option(id)
            let pixels = try Pixels(XCTUnwrap(selection.thumbnail))
            let geometry = BezelLibrary.geometry(for: selection.profile)
            let screen = geometry.screenRect
            let scale = 160 / geometry.frameSize.height
            let gap = pixels.at(screen.midX * scale, (screen.minY + 10) * scale)
            XCTAssertGreaterThan(gap.blueComponent, 0.08, "\(id): visible screen above camera")
            if selection.profile.displayCutout != .none {
                let island = pixels.at(screen.midX * scale, (screen.minY + 70) * scale)
                XCTAssertLessThan(island.blueComponent, 0.055, id)
            }
        }
    }

    func testLandscapeNotchesStayAttachedToTheRotatedRail() throws {
        for (id, shoulder): (String, CGFloat) in [("iphone-12", 230), ("iphone-13", 185)] {
            try autoreleasepool {
                let selection = try option(id)
                let profile = selection.profile.oriented(matching: CGSize(width: 3_000, height: 1_000))
                let frame = try XCTUnwrap(BezelLibrary.frame(for: selection, orientedTo: profile))
                let pixels = try Pixels(frame.image)
                let screen = frame.geometry.screenRect
                for offset in [-shoulder, 0, shoulder] {
                    XCTAssertEqual(pixels.at(screen.maxX - 10, screen.midY + offset).alphaComponent,
                                   1, accuracy: 0.01, id)
                    XCTAssertEqual(pixels.at(screen.maxX - 30, screen.midY + offset).alphaComponent,
                                   1, accuracy: 0.01, id)
                }
                XCTAssertEqual(pixels.at(screen.maxX - 130, screen.midY).alphaComponent,
                               0, accuracy: 0.01, id)
                XCTAssertEqual(pixels.at(screen.minX + 30, screen.midY).alphaComponent,
                               0, accuracy: 0.01, id)
            }
        }
    }

    func testScreenshotsCompositeNotchesAndIslandGapsOverVideo() throws {
        let renderer = BezelRenderer(ciContext: CIContext())
        for (id, shoulder): (String, CGFloat) in [("iphone-12", 230), ("iphone-13", 185),
                                                  ("iphone-14-pro", 0), ("iphone-18-pro", 0)] {
            for landscape in [false, true] {
                try autoreleasepool {
                    let selection = try option(id)
                    let profile = selection.profile.oriented(matching: landscape
                        ? CGSize(width: 3_000, height: 1_000) : selection.profile.screenSize)
                    let frame = try XCTUnwrap(BezelLibrary.frame(for: selection, orientedTo: profile))
                    let buffer = try whiteBuffer(size: profile.screenSize)
                    let screenshot = try XCTUnwrap(renderer.screenshot(from: buffer, profile: profile,
                                                                       customFrame: frame.renderFrame))
                    let pixels = try Pixels(screenshot)
                    let screen = frame.geometry.screenRect
                    func sample(offset: CGFloat, depth: CGFloat) -> NSColor {
                        landscape
                            ? pixels.at(screen.maxX - depth, screen.midY + offset)
                            : pixels.at(screen.midX + offset, screen.minY + depth)
                    }
                    let top = sample(offset: shoulder, depth: 10)
                    if shoulder > 0 {
                        XCTAssertLessThan(top.redComponent, 0.05, "\(id): notch covers captured pixels")
                    } else {
                        XCTAssertGreaterThan(top.redComponent, 0.95, "\(id): video shows above island")
                    }
                    XCTAssertLessThan(sample(offset: 0, depth: 70).redComponent, 0.05, id)
                    XCTAssertGreaterThan(sample(offset: 0, depth: 150).redComponent, 0.95, id)
                }
            }
        }
    }

    private func option(_ profileID: String) throws -> BezelOption {
        let profile = try XCTUnwrap(DeviceProfile.catalog.first { $0.id == profileID })
        return try XCTUnwrap(BezelLibrary.automatic(for: profile))
    }

    private func whiteBuffer(size: CGSize) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                          kCVPixelFormatType_32BGRA, nil, &result), kCVReturnSuccess)
        let buffer = try XCTUnwrap(result)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let data = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        memset(data, 255, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        return buffer
    }

    private struct Pixels {
        private let bitmap: NSBitmapImageRep

        init(_ image: NSImage) throws {
            bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil,
                                                                          context: nil, hints: nil)))
        }

        func at(_ x: CGFloat, _ y: CGFloat) -> NSColor {
            bitmap.colorAt(x: Int(x), y: Int(y))!.usingColorSpace(.deviceRGB)!
        }
    }
}
