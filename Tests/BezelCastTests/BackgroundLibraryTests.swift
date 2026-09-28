import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BezelCast

final class BackgroundLibraryTests: XCTestCase {
    func testBuiltInsLoadWithoutFilesAndHaveStableUniqueIDs() throws {
        let options = BackgroundLibrary.builtIns
        XCTAssertEqual(Set(options.map(\.id)).count, options.count)
        XCTAssertEqual(options.first?.id, "none")
        XCTAssertTrue(try BackgroundLibrary.load(XCTUnwrap(options.first)).isNone)
        for option in options {
            XCTAssertNil(option.fileURL)
            let background = try BackgroundLibrary.load(option)
            XCTAssertEqual(background.id, option.id)
            XCTAssertNotNil(BackgroundLibrary.thumbnail(for: option))
        }
        XCTAssertTrue(options.contains { $0.kind == .gradient })
        XCTAssertTrue(options.contains { $0.kind == .solid })
    }

    func testDiscoveryOffersAvailableImagesAndDeduplicatesCurrentWallpaper() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Installed")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let wallpaper = nested.appendingPathComponent("Ocean.png")
        try writeImage(to: wallpaper, width: 120, height: 60)
        let duplicate = root.appendingPathComponent("Ocean Link.png")
        try FileManager.default.createSymbolicLink(at: duplicate, withDestinationURL: wallpaper)
        try Data("not an image".utf8).write(to: root.appendingPathComponent("Broken.png"))
        try Data("placeholder".utf8).write(to: root.appendingPathComponent("Unavailable.madesktop"))

        for directory in [".thumbnails", "Solid Colors", "Previews"] {
            let excluded = root.appendingPathComponent(directory)
            try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
            try writeImage(to: excluded.appendingPathComponent("Tiny.png"), width: 4, height: 4)
        }
        let options = BackgroundLibrary.wallpapers(in: [root, root.appendingPathComponent("Missing")],
                                                   currentWallpaperURLs: [wallpaper])
        XCTAssertEqual(options.count, 1)
        let found = try XCTUnwrap(options.first)
        XCTAssertEqual(found.name, "Ocean")
        XCTAssertEqual(found.kind, .wallpaper)
        XCTAssertEqual(found.fileURL, wallpaper.resolvingSymlinksInPath())
        XCTAssertNotNil(try BackgroundLibrary.load(found))
    }

    func testCurrentWallpaperOutsideDiscoveryRootsIsAvailable() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("My Wallpaper.png")
        try writeImage(to: url, width: 20, height: 10)
        let options = BackgroundLibrary.wallpapers(in: [], currentWallpaperURLs: [url])
        XCTAssertEqual(options.map(\.name), ["My Wallpaper"])
    }

    func testUserDownloadedOriginalWallpapersAreIncludedInDefaultRoots() {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.mobileAssetDesktop", isDirectory: true)
        XCTAssertTrue(BackgroundLibrary.defaultWallpaperDirectories.contains(root))
    }

    func testDiscoveryExcludesProcessedDesktopCopiesWithoutExcludingOriginals() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let processedDirectory = root.appendingPathComponent("TopNotch/processed", isDirectory: true)
        let originalDirectory = root.appendingPathComponent("com.apple.mobileAssetDesktop", isDirectory: true)
        try FileManager.default.createDirectory(at: processedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        let processed = processedDirectory.appendingPathComponent("Cached.png")
        let original = originalDirectory.appendingPathComponent("Ventura Graphic.png")
        try writeImage(to: processed, width: 80, height: 40, blackBandHeight: 8)
        try writeImage(to: original, width: 80, height: 40)
        let alias = root.appendingPathComponent("Desktop Alias.png")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: processed)

        XCTAssertTrue(BackgroundLibrary.isProcessedDesktopWallpaper(url: processed))
        XCTAssertTrue(BackgroundLibrary.isProcessedDesktopWallpaper(url: alias))
        XCTAssertFalse(BackgroundLibrary.isProcessedDesktopWallpaper(url: original))
        XCTAssertFalse(BackgroundLibrary.isProcessedDesktopWallpaper(url: root.appendingPathComponent("TopNotch/original.png")))
        XCTAssertFalse(BackgroundLibrary.isProcessedDesktopWallpaper(url: root.appendingPathComponent("AnotherApp/processed/photo.png")))
        let options = BackgroundLibrary.wallpapers(in: [root], currentWallpaperURLs: [processed, alias])
        XCTAssertEqual(options.map(\.name), ["Ventura Graphic"])
        XCTAssertNotNil(try BackgroundLibrary.load(XCTUnwrap(options.first)))
    }

    func testSavedProcessedWallpaperCannotLoadOrShowAThumbnail() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("TopNotch/processed", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Cached.png")
        try writeImage(to: url, width: 80, height: 40, blackBandHeight: 8)
        // Loading the same file explicitly as a custom image fills the image
        // cache first; a saved wallpaper must still be rejected afterwards.
        _ = try BackgroundLibrary.load(BackgroundLibrary.customOption(url: url))
        let savedWallpaper = BackgroundLibrary.wallpaperOption(url: url)
        XCTAssertThrowsError(try BackgroundLibrary.load(savedWallpaper)) { error in
            XCTAssertTrue(error.localizedDescription.contains("original installed macOS wallpaper"))
        }
        XCTAssertNil(BackgroundLibrary.thumbnail(for: savedWallpaper))
    }

    func testExplicitCustomProcessedImageRetainsTheWholeImageAndBlackBand() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("TopNotch/processed", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Intentional.png")
        try writeImage(to: url, width: 80, height: 40, blackBandHeight: 8)
        let option = BackgroundLibrary.customOption(url: url)
        let image = try loadedImage(option)
        XCTAssertEqual(image.width, 80)
        XCTAssertEqual(image.height, 40)
        XCTAssertNotNil(BackgroundLibrary.thumbnail(for: option))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                              bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let blackPixels = (0..<(image.width * image.height)).filter {
            bytes[$0 * 4] == 0 && bytes[$0 * 4 + 1] == 0 && bytes[$0 * 4 + 2] == 0
        }.count
        XCTAssertEqual(blackPixels, 80 * 8)
    }

    func testImageAndThumbnailLoadsRespectPixelLimits() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Wide.png")
        try writeImage(to: url, width: 5000, height: 20)
        let option = BackgroundLibrary.customOption(url: url)
        let image = try loadedImage(option)
        XCTAssertEqual(image.width, 4096)
        XCTAssertLessThanOrEqual(image.height, 20)
        let thumbnail = try XCTUnwrap(BackgroundLibrary.thumbnail(for: option, maxPixelSize: 120))
        XCTAssertEqual(thumbnail.width, 120)
        XCTAssertGreaterThan(thumbnail.height, 0)
        XCTAssertNil(BackgroundLibrary.thumbnail(for: option, maxPixelSize: 0))
    }

    func testEXIFOrientationIsAppliedBeforeDisplay() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Portrait.jpg")
        try writeImage(to: url, width: 80, height: 40, orientation: 6)
        let image = try loadedImage(BackgroundLibrary.customOption(url: url))
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 80)
    }

    func testDeletedAndCorruptImagesProduceActionableErrors() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Deleted.png")
        try writeImage(to: url, width: 20, height: 10)
        let option = BackgroundLibrary.customOption(url: url)
        _ = try BackgroundLibrary.load(option)
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try BackgroundLibrary.load(option)) { error in
            XCTAssertTrue(error.localizedDescription.contains("no longer available"))
        }
        try Data("invalid image".utf8).write(to: url)
        XCTAssertThrowsError(try BackgroundLibrary.load(option)) { error in
            XCTAssertTrue(error.localizedDescription.contains("could not be opened"))
        }
    }

    func testReplacingAnImageInvalidatesTheDecodedCache() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Replace.png")
        let option = BackgroundLibrary.customOption(url: url)
        try writeImage(to: url, width: 40, height: 20)
        XCTAssertEqual(try loadedImage(option).width, 40)
        try writeImage(to: url, width: 80, height: 20)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 10)], ofItemAtPath: url.path)
        XCTAssertEqual(try loadedImage(option).width, 80)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BezelCast-BackgroundTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func loadedImage(_ option: BackgroundOption) throws -> CGImage {
        let background = try BackgroundLibrary.load(option)
        guard case .image(let image) = background.content else {
            throw BackgroundLibrary.LoadError.invalidOption
        }
        return image
    }

    private func writeImage(to url: URL, width: Int, height: Int, orientation: Int? = nil,
                            blackBandHeight: Int = 0) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.15, green: 0.45, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if blackBandHeight > 0 {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: height - blackBandHeight, width: width, height: blackBandHeight))
        }
        let image = try XCTUnwrap(context.makeImage())
        let type = orientation == nil ? UTType.png.identifier : UTType.jpeg.identifier
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        let properties = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
