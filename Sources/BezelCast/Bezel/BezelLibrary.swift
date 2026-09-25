import AppKit
import CoreGraphics

/// Original, code-drawn artwork. No Apple Design Resources are embedded.
struct BezelOption: Identifiable, Sendable {
    let profile: DeviceProfile
    let finish: BezelFinish

    var id: String { "\(profile.id)/\(finish.rawValue)" }
    var profileID: String { profile.id }
    var finishName: String { finish.displayName }
    var name: String { "\(profile.displayName) · \(finishName)" }
    var thumbnail: NSImage? { BezelLibrary.thumbnail(for: self) }
}

/// Serializes full-size rasterization and skips obsolete queued selections.
actor BezelFrameLoader {
    static let shared = BezelFrameLoader()

    func frame(for option: BezelOption, orientedTo profile: DeviceProfile) -> CustomFrame? {
        guard !Task.isCancelled else { return nil }
        return BezelLibrary.frame(for: option, orientedTo: profile)
    }
}

enum BezelLibrary {
    static let options: [BezelOption] = DeviceProfile.catalog.flatMap { profile in
        (BezelFinishCatalog.palette(for: profile.id)?.finishes ?? [])
            .map { BezelOption(profile: profile, finish: $0) }
    }

    static func option(id: String) -> BezelOption? {
        options.first { $0.id == id }
    }

    static func compatible(with profile: DeviceProfile) -> [BezelOption] {
        let ids = Set(DeviceProfile.compatible(with: profile).map(\.id))
        return options.filter { ids.contains($0.profileID) }
    }

    static func automatic(for profile: DeviceProfile) -> BezelOption? {
        options.first { $0.profileID == profile.id }
    }

    static func option(for profile: DeviceProfile, preferring finish: BezelFinish) -> BezelOption? {
        option(id: "\(profile.id)/\(finish.rawValue)") ?? automatic(for: profile)
    }

    /// Migrate a previously saved generic finish to an available finish on the
    /// same model. Never turn an invalid color into a selectable library entry.
    static func restoredOption(id: String, compatibleWith reference: DeviceProfile) -> BezelOption? {
        let modelID = id.split(separator: "/", maxSplits: 1).first.map(String.init)
        guard let model = DeviceProfile.compatible(with: reference).first(where: { $0.id == modelID }) else {
            return nil
        }
        return option(id: id) ?? automatic(for: model)
    }

    private static let frames: NSCache<NSString, FrameBox> = {
        let cache = NSCache<NSString, FrameBox>()
        cache.totalCostLimit = 96 * 1024 * 1024
        cache.countLimit = 3
        return cache
    }()
    private static let thumbnails = NSCache<NSString, NSImage>()

    static func frame(for option: BezelOption, orientedTo profile: DeviceProfile) -> CustomFrame? {
        if let cached = frames.object(forKey: option.id as NSString) {
            return cached.frame.oriented(to: profile)
        }
        let geometry = geometry(for: option.profile)
        guard let cgImage = draw(option, geometry: geometry, scale: 1, thumbnail: false),
              let frame = CustomFrame.make(name: option.name,
                                           image: NSImage(cgImage: cgImage, size: geometry.frameSize),
                                           cgImage: cgImage,
                                           geometry: geometry,
                                           profile: option.profile) else { return nil }
        frames.setObject(FrameBox(frame), forKey: option.id as NSString,
                         cost: cgImage.width * cgImage.height * 8)
        return frame.oriented(to: profile)
    }

    static func thumbnail(for option: BezelOption) -> NSImage? {
        if let cached = thumbnails.object(forKey: option.id as NSString) { return cached }
        let geometry = geometry(for: option.profile)
        let scale = 160 / geometry.frameSize.height
        guard let image = draw(option, geometry: geometry, scale: scale, thumbnail: true) else { return nil }
        let result = NSImage(cgImage: image,
                             size: CGSize(width: geometry.frameSize.width * scale / 2, height: 80))
        thumbnails.setObject(result, forKey: option.id as NSString)
        return result
    }

    /// Geometry belongs to the artwork, independently of any Apple PNG size.
    static func geometry(for profile: DeviceProfile) -> FrameGeometry {
        let screen = profile.screenSize
        let homeButton = profile.screenCornerRadius == 0
        let side: CGFloat = profile.family == .iPad ? 64 : 42
        let vertical: CGFloat = homeButton ? (profile.family == .iPad ? 180 : 190) : side
        return FrameGeometry(frameSize: CGSize(width: screen.width + side * 2 + 12,
                                               height: screen.height + vertical * 2),
                             screenRect: CGRect(x: side + 6, y: vertical,
                                                width: screen.width, height: screen.height))
    }

    private static func draw(_ option: BezelOption, geometry: FrameGeometry,
                             scale: CGFloat, thumbnail: Bool) -> CGImage? {
        let size = geometry.frameSize
        guard let context = CGContext(data: nil,
                                       width: Int(ceil(size.width * scale)),
                                       height: Int(ceil(size.height * scale)),
                                       bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        // Draw in top-left coordinates, matching FrameGeometry and rotatedFrame.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        let screen = geometry.screenRect
        let radius = option.profile.screenCornerRadius
        let body = CGRect(x: 6, y: 0, width: size.width - 12, height: size.height)
        let outerRadius = radius > 0 ? radius + screen.minX - 6 : 96
        guard let palette = BezelFinishCatalog.palette(for: option.profileID) else { return nil }
        let (r, g, b) = palette.components(for: option.finish)
        let frontColor = CGColor(gray: palette.lightFront && option.finish != .spaceGray ? 0.94 : 0.025, alpha: 1)
        func color(_ factor: CGFloat) -> CGColor {
            CGColor(red: min(1, r * factor), green: min(1, g * factor),
                    blue: min(1, b * factor), alpha: 1)
        }
        func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
            CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        context.setFillColor(color(0.9))
        // Side controls remain outside the display cutout.
        for rect in [CGRect(x: 0, y: size.height * 0.19, width: 12, height: 82),
                     CGRect(x: 0, y: size.height * 0.26, width: 12, height: 130),
                     CGRect(x: size.width - 12, y: size.height * 0.25, width: 12, height: 190)] {
            context.addPath(rounded(rect, 5)); context.fillPath()
        }
        context.saveGState()
        context.addPath(rounded(body, outerRadius)); context.clip()
        let colors = [color(1.45), color(0.72), color(1.1), color(0.6)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                     locations: [0, 0.35, 0.65, 1]) {
            context.drawLinearGradient(gradient, start: .zero,
                                       end: CGPoint(x: size.width, y: size.height), options: [])
        }
        context.restoreGState()
        context.setStrokeColor(color(1.65)); context.setLineWidth(3)
        context.addPath(rounded(body.insetBy(dx: 3, dy: 3), outerRadius - 3)); context.strokePath()
        context.setFillColor(frontColor)
        context.addPath(rounded(body.insetBy(dx: 11, dy: 11), outerRadius - 11)); context.fillPath()
        context.setBlendMode(.clear)
        context.addPath(rounded(screen, radius)); context.fillPath()
        context.setBlendMode(.normal)
        if thumbnail {
            context.setFillColor(CGColor(red: 0.09, green: 0.12, blue: 0.18, alpha: 1))
            context.addPath(rounded(screen, radius)); context.fillPath()
        }
        context.setFillColor(CGColor(gray: 0.015, alpha: 1))
        if radius == 0 {
            context.setFillColor(frontColor)
            let diameter: CGFloat = option.profile.family == .iPhone ? 100 : 84
            let centerY = screen.maxY + (size.height - screen.maxY) / 2
            context.setStrokeColor(color(0.95)); context.setLineWidth(4)
            context.addEllipse(in: CGRect(x: size.width / 2 - diameter / 2, y: centerY - diameter / 2,
                                          width: diameter, height: diameter)); context.drawPath(using: .fillStroke)
        } else if let cutout = option.profile.displayCutout.path(in: screen,
                                                                 displayScale: option.profile.displayScale) {
            context.addPath(cutout)
            context.fillPath()
        }
        return context.makeImage()
    }

    private final class FrameBox {
        let frame: CustomFrame
        init(_ frame: CustomFrame) { self.frame = frame }
    }
}
