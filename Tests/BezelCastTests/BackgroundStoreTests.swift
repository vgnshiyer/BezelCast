import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BezelCast

@MainActor
final class BackgroundStoreTests: XCTestCase {
    func testBackgroundAndLayoutPreferencesRestoreWithoutChangingTheDefault() throws {
        try withStore { store, preferences, directory in
            XCTAssertTrue(store.background.isNone)
            store.select("gradient:ocean")
            store.setCanvas(.square)
            store.setPadding(0.2)
            store.setShadow(false)
            let restored = BackgroundStore(preferences: preferences, importDirectory: directory)
            XCTAssertEqual(restored.selectedID, "gradient:ocean")
            XCTAssertEqual(restored.canvas, .square)
            XCTAssertEqual(restored.padding, 0.2)
            XCTAssertFalse(restored.shadow)
            restored.select("none")
            XCTAssertTrue(BackgroundStore(preferences: preferences, importDirectory: directory).background.isNone)
        }
    }

    func testChoosingNoneWhileAnImageLoadsCannotRestoreTheOldChoice() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.store()
        let url = try fixture.image()
        store.importImage(from: url)
        store.select("none")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(store.background.isNone)
        XCTAssertEqual(store.selectedID, "none")
        XCTAssertFalse(store.isLoading)
    }

    func testImportedImageRestoresAfterTheOriginalFileIsRemoved() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.store()
        let url = try fixture.image()
        store.importImage(from: url)
        try await waitUntil { !store.isLoading }
        XCTAssertNil(store.error)
        XCTAssertFalse(store.background.isNone)
        let importedID = store.selectedID
        try FileManager.default.removeItem(at: url)
        let restored = fixture.store()
        try await waitUntil { !restored.isLoading }
        XCTAssertEqual(restored.selectedID, importedID)
        XCTAssertNil(restored.error)
        restored.select("none")
        let unselected = fixture.store()
        XCTAssertTrue(unselected.options.contains { $0.id == importedID })
    }

    func testUnreadableImportKeepsTheCurrentBackgroundAndReportsAnError() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.store()
        store.select("solid:sand")
        store.importImage(from: fixture.directory.appendingPathComponent("missing.png"))
        try await waitUntil { !store.isLoading }
        XCTAssertEqual(store.selectedID, "solid:sand")
        XCTAssertNotNil(store.error)
    }

    func testSavedProcessedWallpaperIsRemovedWithoutSubstitutingOtherArtwork() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = fixture.directory.appendingPathComponent("TopNotch/processed/Cached.png")
        let option = BackgroundLibrary.wallpaperOption(url: url)
        fixture.preferences.set(option.id, forKey: "BezelCast.background.id")
        fixture.preferences.set(url.path, forKey: "BezelCast.background.wallpaperPath")
        fixture.preferences.set("portrait", forKey: "BezelCast.background.canvas")
        let store = fixture.store()
        XCTAssertTrue(store.background.isNone)
        XCTAssertEqual(store.selectedID, "none")
        XCTAssertEqual(store.canvas, .portrait)
        XCTAssertFalse(store.options.contains { $0.id == option.id })
        XCTAssertTrue(try XCTUnwrap(store.error).contains("macOS Wallpapers"))
        XCTAssertEqual(fixture.preferences.string(forKey: "BezelCast.background.id"), "none")
        XCTAssertNil(fixture.preferences.string(forKey: "BezelCast.background.wallpaperPath"))

        store.select("gradient:ocean")
        XCTAssertNil(store.error)
        XCTAssertEqual(fixture.store().selectedID, "gradient:ocean")
    }

    func testSavedOriginalWallpaperStillRestores() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.image()
        let option = BackgroundLibrary.wallpaperOption(url: url)
        fixture.preferences.set(option.id, forKey: "BezelCast.background.id")
        fixture.preferences.set(url.path, forKey: "BezelCast.background.wallpaperPath")
        let store = fixture.store()
        try await waitUntil { !store.isLoading }
        XCTAssertEqual(store.selectedID, option.id)
        XCTAssertFalse(store.background.isNone)
        XCTAssertNil(store.error)
    }

    func testBezelChangesRetainTheBackgroundInTheCaptureConfiguration() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let capture = DeviceCapture(preferences: fixture.preferences, startCapture: false)
        capture.backgrounds.select("gradient:dusk")
        capture.backgrounds.setCanvas(.portrait)
        capture.backgrounds.setPadding(0.15)
        capture.selectBezel("iphone-13-mini/midnight")
        try await waitUntil { capture.profile.id == "iphone-13-mini" }
        let presentation = capture.previewConfiguration.presentation
        XCTAssertEqual(presentation.background.id, "gradient:dusk")
        XCTAssertEqual(presentation.outputSize(for: capture.profile.screenSize), CGSize(width: 1080, height: 1920))
        XCTAssertEqual(presentation.padding, 0.15)
        capture.selectBezel("none")
        XCTAssertEqual(capture.previewConfiguration.presentation.background.id, "gradient:dusk")
        capture.backgrounds.select("none")
        XCTAssertEqual(capture.previewConfiguration.presentation.outputSize(for: capture.profile.screenSize),
                       capture.profile.screenSize)
    }

    private func withStore(_ action: (BackgroundStore, UserDefaults, URL) throws -> Void) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try action(fixture.store(), fixture.preferences, fixture.directory)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), "Background update timed out")
    }

    private struct Fixture {
        let suite = "BackgroundStoreTests.\(UUID())"
        let preferences: UserDefaults
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        init() throws {
            preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        @MainActor func store() -> BackgroundStore {
            BackgroundStore(preferences: preferences, importDirectory: directory.appendingPathComponent("Imported"))
        }

        func image() throws -> URL {
            let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8,
                                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(NSColor.systemBlue.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
            let url = directory.appendingPathComponent("Custom.png")
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return url
        }

        func cleanUp() {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
