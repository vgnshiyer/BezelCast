import CoreGraphics
import Foundation
import ImageIO

struct BackgroundColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.component(red)
        self.green = Self.component(green)
        self.blue = Self.component(blue)
    }

    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: 1) }

    private static func component(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

struct CaptureBackground: @unchecked Sendable {
    enum Content {
        case none
        case solid(BackgroundColor)
        case gradient(BackgroundColor, BackgroundColor)
        case image(CGImage)
    }

    let id: String
    let name: String
    let content: Content

    static let none = CaptureBackground(id: "none", name: "None", content: .none)

    var isNone: Bool {
        if case .none = content { return true }
        return false
    }
}

struct BackgroundOption: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case none, solid, gradient, wallpaper, custom
    }

    let id: String
    let name: String
    let kind: Kind
    let fileURL: URL?
    let colors: [BackgroundColor]

    init(id: String, name: String, kind: Kind, fileURL: URL? = nil,
         colors: [BackgroundColor] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.fileURL = fileURL
        self.colors = colors
    }
}

enum BackgroundLibrary {
    static let builtIns: [BackgroundOption] = [
        BackgroundOption(id: "none", name: "None", kind: .none),
        solid("white", "White", 1, 1, 1),
        solid("graphite", "Graphite", 0.12, 0.13, 0.15),
        solid("black", "Black", 0, 0, 0),
        solid("sand", "Sand", 0.91, 0.86, 0.77),
        gradient("dusk", "Dusk", (0.22, 0.14, 0.46), (0.92, 0.46, 0.51)),
        gradient("ocean", "Ocean", (0.06, 0.21, 0.44), (0.22, 0.73, 0.77)),
        gradient("aurora", "Aurora", (0.11, 0.36, 0.37), (0.61, 0.72, 0.40)),
        gradient("sunrise", "Sunrise", (0.97, 0.48, 0.31), (0.99, 0.82, 0.54))
    ]

    static let defaultWallpaperDirectories = [
        URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true),
        URL(fileURLWithPath: "/Library/Desktop Pictures", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture", isDirectory: true),
        URL(fileURLWithPath: "/Library/AssetsV2/com_apple_MobileAsset_DesktopPicture", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.mobileAssetDesktop", isDirectory: true)
    ]

    /// Desktop APIs can return TopNotch's edited copy with a black menu-bar
    /// strip baked in. Follow symlinks, but do not guess a corresponding original.
    static func isProcessedDesktopWallpaper(url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            .map { $0.lowercased() }
        return zip(components, components.dropFirst()).contains {
            $0 == "topnotch" && $1 == "processed"
        }
    }

    /// Reads installed images only. A .madesktop file is often just a download
    /// descriptor with a tiny thumbnail, so it is not a selectable wallpaper.
    static func wallpapers(in roots: [URL] = defaultWallpaperDirectories,
                           currentWallpaperURLs: [URL] = []) -> [BackgroundOption] {
        let manager = FileManager.default
        var candidates = currentWallpaperURLs
        for root in roots {
            guard let enumerator = manager.enumerator(at: root,
                                                      includingPropertiesForKeys: [.isRegularFileKey],
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                // System solid colors duplicate our built-in choices. Preview
                // directories are deliberately excluded even in MobileAssets.
                if ["Solid Colors", "Thumbnails", "thumbnails", "Previews"].contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                guard imageExtensions.contains(url.pathExtension.lowercased()),
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                candidates.append(url)
            }
        }

        var seen = Set<URL>()
        return candidates.compactMap { url in
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard url.isFileURL, seen.insert(resolved).inserted,
                  !isProcessedDesktopWallpaper(url: resolved),
                  imageExtensions.contains(url.pathExtension.lowercased()),
                  (try? image(at: resolved, maxPixelSize: 32)) != nil else { return nil }
            return wallpaperOption(url: resolved)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func customOption(url: URL) -> BackgroundOption {
        fileOption(url: url, kind: .custom, prefix: "custom")
    }

    static func wallpaperOption(url: URL, name: String? = nil) -> BackgroundOption {
        fileOption(url: url, kind: .wallpaper, prefix: "wallpaper", name: name)
    }

    static func load(_ option: BackgroundOption, maxPixelSize: Int = 4096) throws -> CaptureBackground {
        let content: CaptureBackground.Content
        switch option.kind {
        case .none:
            return .none
        case .solid:
            guard let color = option.colors.first else { throw LoadError.invalidOption }
            content = .solid(color)
        case .gradient:
            guard option.colors.count == 2 else { throw LoadError.invalidOption }
            content = .gradient(option.colors[0], option.colors[1])
        case .wallpaper, .custom:
            guard let url = option.fileURL else { throw LoadError.invalidOption }
            if option.kind == .wallpaper && isProcessedDesktopWallpaper(url: url) {
                throw LoadError.processedDesktopWallpaper
            }
            content = .image(try image(at: url, maxPixelSize: maxPixelSize))
        }
        return CaptureBackground(id: option.id, name: option.name, content: content)
    }

    static func thumbnail(for option: BackgroundOption, maxPixelSize: Int = 160) -> CGImage? {
        guard maxPixelSize > 0 else { return nil }
        if let url = option.fileURL {
            guard option.kind != .wallpaper || !isProcessedDesktopWallpaper(url: url) else { return nil }
            return try? image(at: url, maxPixelSize: maxPixelSize)
        }
        let width = min(maxPixelSize, 1024)
        let height = max(1, width * 2 / 3)
        guard let background = try? load(option),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        switch background.content {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case .gradient(let start, let end):
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: [start.cgColor, end.cgColor] as CFArray,
                                            locations: [0, 1]) else { return nil }
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height),
                                       end: CGPoint(x: width, y: 0), options: [])
        case .none:
            context.clear(rect)
        case .image:
            return nil
        }
        return context.makeImage()
    }

    enum LoadError: LocalizedError {
        case unavailableFile(URL)
        case unsupportedImage(URL)
        case processedDesktopWallpaper
        case invalidOption

        var errorDescription: String? {
            switch self {
            case .unavailableFile(let url):
                return "The background image \"\(url.lastPathComponent)\" is no longer available. Choose another image."
            case .unsupportedImage(let url):
                return "The file \"\(url.lastPathComponent)\" could not be opened as an image."
            case .processedDesktopWallpaper:
                return "TopNotch modifies this desktop image. Choose an original installed macOS wallpaper instead."
            case .invalidOption:
                return "This background could not be loaded. Choose another background."
            }
        }
    }

    private static let imageExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tif", "tiff", "webp"]
    private static let images: NSCache<NSString, ImageBox> = {
        let cache = NSCache<NSString, ImageBox>()
        cache.countLimit = 16
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

    private static func image(at url: URL, maxPixelSize: Int) throws -> CGImage {
        guard maxPixelSize > 0 else { throw LoadError.invalidOption }
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular else { throw LoadError.unavailableFile(url) }
        let limit = min(maxPixelSize, 8192)
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let key = "\(url.standardizedFileURL.absoluteString)|\(modified)|\(size)|\(limit)" as NSString
        if let cached = images.object(forKey: key) { return cached.image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw LoadError.unsupportedImage(url) }
        // ImageIO applies EXIF rotation before returning a bounded bitmap, so
        // importing a portrait phone photo neither rotates it nor allocates its
        // full camera resolution in every captured frame.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true
        ]
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let result = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw LoadError.unsupportedImage(url)
        }
        images.setObject(ImageBox(result), forKey: key, cost: result.bytesPerRow * result.height)
        return result
    }

    private static func fileOption(url: URL, kind: BackgroundOption.Kind, prefix: String,
                                   name: String? = nil) -> BackgroundOption {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        return BackgroundOption(id: "\(prefix):\(canonical.absoluteString)",
                                name: name ?? canonical.deletingPathExtension().lastPathComponent,
                                kind: kind, fileURL: canonical)
    }

    private static func solid(_ id: String, _ name: String, _ r: Double, _ g: Double, _ b: Double) -> BackgroundOption {
        BackgroundOption(id: "solid:\(id)", name: name, kind: .solid,
                         colors: [BackgroundColor(red: r, green: g, blue: b)])
    }

    private static func gradient(_ id: String, _ name: String,
                                 _ first: (Double, Double, Double), _ second: (Double, Double, Double)) -> BackgroundOption {
        BackgroundOption(id: "gradient:\(id)", name: name, kind: .gradient,
                         colors: [BackgroundColor(red: first.0, green: first.1, blue: first.2),
                                  BackgroundColor(red: second.0, green: second.1, blue: second.2)])
    }

    private final class ImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
}
