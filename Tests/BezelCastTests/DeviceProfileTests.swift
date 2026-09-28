import CoreGraphics
import XCTest
@testable import BezelCast

final class DeviceProfileTests: XCTestCase {
    func testXRAnd11ResolutionDetectsNewestMatchingModelInBothOrientations() throws {
        // XR and 11 share a resolution; detection chooses the newest catalog
        // entry, while the bezel picker lets the user select XR explicitly.
        for size in [CGSize(width: 828, height: 1792), CGSize(width: 1792, height: 828)] {
            let detected = try XCTUnwrap(DeviceProfile.detect(for: size))
            XCTAssertEqual(detected.id, "iphone-11")
            XCTAssertEqual(detected.screenSize, size)
            XCTAssertEqual(detected.isLandscape, size.width > size.height)
        }
    }

    func testXRAnd11UseTheirNativeScaleAndWideNotchGeometry() throws {
        for id in ["iphone-xr", "iphone-11"] {
            let profile = try XCTUnwrap(DeviceProfile.catalog.first { $0.id == id }, id)
            XCTAssertEqual(profile.screenSize, CGSize(width: 828, height: 1792), id)
            XCTAssertEqual(profile.displayScale, 2, id)
            XCTAssertEqual(profile.screenCornerRadius, 83, id)
            XCTAssertEqual(profile.displayCutout, .wideNotch, id)

            let landscape = profile.oriented(matching: CGSize(width: 1792, height: 828))
            XCTAssertEqual(landscape.displayScale, 2, id)
            XCTAssertEqual(landscape.screenCornerRadius, 83, id)
            XCTAssertEqual(landscape.displayCutout, .wideNotch, id)
            XCTAssertEqual(landscape.oriented(matching: profile.screenSize), profile, id)
        }
    }
}
