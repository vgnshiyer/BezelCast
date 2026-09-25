import Foundation
import XCTest
@testable import BezelCast

final class ReleasedFinishTests: XCTestCase {
    func testRecentIPhonesOfferExactlyTheirReleasedFinishes() throws {
        // Independently verified against Apple's technical specifications.
        // Keep Pro/Max and standard/Plus assertions separate so a missing
        // per-model assignment cannot silently borrow another model's palette.
        let expected: [String: Set<BezelFinish>] = [
            "iphone-18-pro-max": [.black, .silver, .glacier, .burgundy],
            "iphone-18-pro": [.black, .silver, .glacier, .burgundy],
            "iphone-17-pro-max": [.silver, .cosmicOrange, .deepBlue],
            "iphone-17-pro": [.silver, .cosmicOrange, .deepBlue],
            "iphone-17": [.black, .white, .mistBlue, .sage, .lavender],
            "iphone-air": [.spaceBlack, .cloudWhite, .lightGold, .skyBlue],
            "iphone-17e": [.black, .white, .softPink],
            "iphone-16-pro-max": [.blackTitanium, .whiteTitanium, .naturalTitanium, .desertTitanium],
            "iphone-16-pro": [.blackTitanium, .whiteTitanium, .naturalTitanium, .desertTitanium],
            "iphone-16-plus": [.black, .white, .pink, .teal, .ultramarine],
            "iphone-16": [.black, .white, .pink, .teal, .ultramarine],
            "iphone-16e": [.black, .white]
        ]

        for (profileID, finishes) in expected {
            let palette = try XCTUnwrap(BezelFinishCatalog.palette(for: profileID), profileID)
            XCTAssertEqual(Set(palette.finishes), finishes, profileID)
            let options = BezelLibrary.options.filter { $0.profileID == profileID }
            XCTAssertEqual(Set(options.map(\.finish)), finishes, profileID)
            XCTAssertEqual(options.count, finishes.count, profileID)
        }
    }

    func testEverySelectableModelHasAnExplicitAppleSourcedPalette() throws {
        XCTAssertEqual(Set(DeviceProfile.catalog.map(\.id)).count, DeviceProfile.catalog.count)
        XCTAssertEqual(Set(BezelLibrary.options.map(\.id)).count, BezelLibrary.options.count)

        for profile in DeviceProfile.catalog {
            let palette = try XCTUnwrap(BezelFinishCatalog.palette(for: profile.id), profile.id)
            XCTAssertFalse(palette.finishes.isEmpty, profile.id)
            XCTAssertEqual(Set(palette.finishes).count, palette.finishes.count, profile.id)
            XCTAssertFalse(palette.sources.isEmpty, profile.id)
            for source in palette.sources {
                let url = try XCTUnwrap(URL(string: source), source)
                XCTAssertEqual(url.scheme, "https", source)
                let host = try XCTUnwrap(url.host, source)
                XCTAssertTrue(host == "apple.com" || host.hasSuffix(".apple.com"), source)
            }

            let options = BezelLibrary.options.filter { $0.profileID == profile.id }
            XCTAssertEqual(Set(options.map(\.finish)), Set(palette.finishes), profile.id)
            XCTAssertEqual(options.count, palette.finishes.count, profile.id)
            for option in options {
                XCTAssertEqual(BezelLibrary.option(id: option.id)?.name, option.name, option.id)
                XCTAssertFalse(option.finishName.contains("-"), option.name)
            }
        }
        XCTAssertNil(BezelFinishCatalog.palette(for: "unrecognized-device"))
        XCTAssertFalse(BezelLibrary.options.contains { $0.finish.rawValue == "copper" })
    }

    func testAutomaticSelectionUsesAReleasedDefaultForEveryModel() throws {
        for profile in DeviceProfile.catalog {
            let palette = try XCTUnwrap(BezelFinishCatalog.palette(for: profile.id), profile.id)
            let option = try XCTUnwrap(BezelLibrary.automatic(for: profile), profile.id)
            XCTAssertEqual(option.profileID, profile.id)
            XCTAssertEqual(option.finish, palette.finishes.first, profile.id)
            XCTAssertNotNil(BezelLibrary.option(id: option.id), profile.id)
        }
    }

    func testReleasedFinishFilteringPreservesDeviceCompatibility() throws {
        let reference = try XCTUnwrap(DeviceProfile.catalog.first { $0.id == "iphone-18-pro" })
        let choices = BezelLibrary.compatible(with: reference)
        XCTAssertTrue(choices.contains { $0.profileID == "iphone-air" && $0.finish == .skyBlue })
        XCTAssertFalse(choices.contains { $0.profile.family == .iPad })
        XCTAssertFalse(choices.contains { $0.profileID == "iphone-se" })
        XCTAssertEqual(Set(choices.filter { $0.profileID == "iphone-16e" }.map(\.finish)),
                       Set([BezelFinish.black, .white]))
    }

    func testFinishNamesKeepApplesSpacingAndBranding() throws {
        let examples = [
            "iphone-17-pro/cosmic-orange": "Cosmic Orange",
            "iphone-air/space-black": "Space Black",
            "iphone-16-pro/black-titanium": "Black Titanium"
        ]
        for (id, displayName) in examples {
            XCTAssertEqual(try XCTUnwrap(BezelLibrary.option(id: id), id).finishName, displayName)
        }
        let red = try XCTUnwrap(BezelLibrary.options.first {
            $0.profileID == "iphone-se" && $0.finish.displayName == "(PRODUCT)RED"
        })
        XCTAssertEqual(red.finishName, "(PRODUCT)RED")
    }
}
