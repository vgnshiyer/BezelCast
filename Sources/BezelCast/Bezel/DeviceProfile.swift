import CoreGraphics

enum DeviceFamily: Sendable {
    case iPhone
    case iPad
}

struct DeviceProfile: Equatable, Sendable {
    let id: String
    let displayName: String
    let family: DeviceFamily

    /// Native screen pixel resolution. Used for matching against the captured feed.
    let screenSize: CGSize
    /// Native scale factor. Preview/window layout uses display points so iPads
    /// look physically larger than iPhones instead of merely pixel-similar.
    let displayScale: CGFloat
    /// Legacy preset bezel canvas dimensions. Profiles without a verified
    /// preset use `screenSize`; custom frames detect their canvas from the PNG.
    /// Without a custom bezel, exports use `screenSize` directly.
    let frameSize: CGSize
    /// Top-left of the screen within a preset frame, image-data coords (y from
    /// top). Profiles without a preset use zero.
    let screenOffset: CGPoint
    /// Screen corner radius in screen-pixel units (Apple's _displayCornerRadius
    /// per model).
    let screenCornerRadius: CGFloat
    /// Physical camera shape. Resolution and corner radius cannot distinguish
    /// a notch from a Dynamic Island; each catalog model declares its own.
    let displayCutout: DisplayCutout

    var aspectRatio: CGFloat {
        min(screenSize.width, screenSize.height) / max(screenSize.width, screenSize.height)
    }
    var isLandscape: Bool { screenSize.width > screenSize.height }
    var displaySize: CGSize {
        CGSize(width: screenSize.width / displayScale,
               height: screenSize.height / displayScale)
    }
    var hasPresetFrameGeometry: Bool { family == .iPhone && frameSize != screenSize }
    var defaultFrameGeometry: FrameGeometry {
        FrameGeometry(frameSize: frameSize,
                      screenRect: CGRect(origin: screenOffset, size: screenSize))
    }
    func scaledCornerRadius(for renderedScreenSize: CGSize) -> CGFloat {
        screenCornerRadius * min(renderedScreenSize.width / screenSize.width,
                                 renderedScreenSize.height / screenSize.height)
    }

    /// Profiles whose aspect ratio is within `tolerance` of `reference`. Used
    /// to filter the picker — rendering an iPhone SE feed inside an iPhone Pro
    /// bezel (or vice versa) stretches the screen content unusably, so those
    /// combinations are hidden.
    static func compatible(with reference: DeviceProfile,
                           tolerance: CGFloat = 0.05) -> [DeviceProfile] {
        let target = reference.aspectRatio
        let landscape = reference.screenSize.width > reference.screenSize.height
        return catalog.compactMap { profile in
            guard profile.family == reference.family,
                  abs(profile.aspectRatio - target) < tolerance else { return nil }

            return profile.withOrientation(landscape: landscape)
        }
    }

    static func largestDisplaySize(for family: DeviceFamily, matching orientation: CGSize) -> CGSize {
        let landscape = orientation.width > orientation.height
        let profiles = catalog.filter { $0.family == family }
        let sizes = profiles.map { oriented($0.displaySize, landscape: landscape) }
        let w = sizes.map(\.width).max() ?? 0
        let h = sizes.map(\.height).max() ?? 0
        return CGSize(width: w, height: h)
    }
}

extension DeviceProfile {
    /// Catalog of recognized devices. Order is user-facing: newest generation
    /// first, then Pro Max, Pro, Air/Plus, standard, e, mini. detect(for:) returns
    /// the first resolution match, so models sharing a resolution must keep
    /// their newest/default choice first.
    static let catalog: [DeviceProfile] = [
        // Released September 2026. Native resolutions verified against
        // https://www.apple.com/iphone-18-pro/specs/.
        iPhone(id: "iphone-18-pro-max", name: "iPhone 18 Pro Max",
               screenSize: CGSize(width: 1320, height: 2868), cornerRadius: 186, cutout: .compactDynamicIsland),
        iPhone(id: "iphone-18-pro", name: "iPhone 18 Pro",
               screenSize: CGSize(width: 1206, height: 2622), cornerRadius: 186, cutout: .compactDynamicIsland),

        // iPhone 17 family
        proMax(id: "iphone-17-pro-max",  name: "iPhone 17 Pro Max", cutout: .dynamicIsland),
        pro(id: "iphone-17-pro", name: "iPhone 17 Pro", cutout: .dynamicIsland),
        // https://www.apple.com/iphone-air/specs/
        iPhone(id: "iphone-air", name: "iPhone Air",
               screenSize: CGSize(width: 1260, height: 2736), cornerRadius: 186, cutout: .dynamicIsland),
        pro(id: "iphone-17",     name: "iPhone 17", cutout: .dynamicIsland),
        // https://www.apple.com/iphone-17e/specs/
        iPhone(id: "iphone-17e", name: "iPhone 17e",
               screenSize: CGSize(width: 1170, height: 2532), cornerRadius: 142, cutout: .notch),

        // iPhone 16 family
        proMax(id: "iphone-16-pro-max",  name: "iPhone 16 Pro Max", cutout: .dynamicIsland),
        pro(id: "iphone-16-pro", name: "iPhone 16 Pro", cutout: .dynamicIsland),
        proMax2796(id: "iphone-16-plus", name: "iPhone 16 Plus", cutout: .dynamicIsland),
        standard(id: "iphone-16",        name: "iPhone 16", cutout: .dynamicIsland),
        // https://support.apple.com/en-us/122208
        iPhone(id: "iphone-16e", name: "iPhone 16e",
               screenSize: CGSize(width: 1170, height: 2532), cornerRadius: 142, cutout: .notch),

        // iPhone 15 family
        proMax2796(id: "iphone-15-pro-max", name: "iPhone 15 Pro Max", cutout: .dynamicIsland),
        standard(id: "iphone-15-pro",       name: "iPhone 15 Pro", cutout: .dynamicIsland),
        proMax2796(id: "iphone-15-plus",    name: "iPhone 15 Plus", cutout: .dynamicIsland),
        standard(id: "iphone-15",           name: "iPhone 15", cutout: .dynamicIsland),

        // iPhone 14 family
        proMax2796(id: "iphone-14-pro-max",  name: "iPhone 14 Pro Max", cutout: .dynamicIsland),
        standard(id: "iphone-14-pro",        name: "iPhone 14 Pro", cutout: .dynamicIsland),
        proMaxNotched(id: "iphone-14-plus",  name: "iPhone 14 Plus", cutout: .notch),
        standardNotched(id: "iphone-14",     name: "iPhone 14", cutout: .notch),

        // iPhone 13 family
        proMaxNotched(id: "iphone-13-pro-max", name: "iPhone 13 Pro Max", cutout: .notch),
        standardNotched(id: "iphone-13-pro",   name: "iPhone 13 Pro", cutout: .notch),
        standardNotched(id: "iphone-13",       name: "iPhone 13", cutout: .notch),
        mini(id: "iphone-13-mini",             name: "iPhone 13 mini", cutout: .notch),

        // iPhone 12 family
        proMaxNotched(id: "iphone-12-pro-max", name: "iPhone 12 Pro Max", cutout: .wideNotch),
        standardNotched(id: "iphone-12-pro",   name: "iPhone 12 Pro", cutout: .wideNotch),
        standardNotched(id: "iphone-12",       name: "iPhone 12", cutout: .wideNotch),
        mini(id: "iphone-12-mini",             name: "iPhone 12 mini", cutout: .wideNotch),

        // 750×1334 — iPhone SE (3rd gen) — home button, no rounded screen
        DeviceProfile(
            id: "iphone-se",
            displayName: "iPhone SE",
            family: .iPhone,
            screenSize: CGSize(width: 750, height: 1334),
            displayScale: 2,
            frameSize: CGSize(width: 870, height: 1454),
            screenOffset: CGPoint(x: 60, y: 60),
            screenCornerRadius: 0,
            displayCutout: .none
        ),

        // Keep models with different released finishes separate even when they
        // share a screen resolution. Historical IDs remain stable for saved
        // selections and custom frames; their labels now identify precise models.
        iPad(id: "ipad-pro-13", name: "iPad Pro 13-inch (M4/M5)",
             screenSize: CGSize(width: 2064, height: 2752), cornerRadius: 36),
        iPad(id: "ipad-pro-12-9-air-13", name: "iPad Pro 12.9-inch (2018-2022)",
             screenSize: CGSize(width: 2048, height: 2732), cornerRadius: 36),
        iPad(id: "ipad-air-13", name: "iPad Air 13-inch (M2/M3/M4)",
             screenSize: CGSize(width: 2048, height: 2732), cornerRadius: 36),
        iPad(id: "ipad-pro-12-9-home-button", name: "iPad Pro 12.9-inch (1st/2nd gen)",
             screenSize: CGSize(width: 2048, height: 2732), cornerRadius: 0),
        iPad(id: "ipad-pro-11-m4", name: "iPad Pro 11-inch (M4/M5)",
             screenSize: CGSize(width: 1668, height: 2420), cornerRadius: 36),
        iPad(id: "ipad-pro-11", name: "iPad Pro 11-inch (2018-2022)",
             screenSize: CGSize(width: 1668, height: 2388), cornerRadius: 36),
        iPad(id: "ipad-11-air-11", name: "iPad (A16 / 10th gen)",
             screenSize: CGSize(width: 1640, height: 2360), cornerRadius: 36),
        iPad(id: "ipad-air-11", name: "iPad Air 11-inch (M2/M3/M4)",
             screenSize: CGSize(width: 1640, height: 2360), cornerRadius: 36),
        iPad(id: "ipad-air-10-9-5", name: "iPad Air 10.9-inch (5th gen)",
             screenSize: CGSize(width: 1640, height: 2360), cornerRadius: 36),
        iPad(id: "ipad-air-10-9-4", name: "iPad Air 10.9-inch (4th gen)",
             screenSize: CGSize(width: 1640, height: 2360), cornerRadius: 36),
        iPad(id: "ipad-mini-8-3", name: "iPad mini (A17 Pro)",
             screenSize: CGSize(width: 1488, height: 2266), cornerRadius: 36),
        iPad(id: "ipad-mini-8-3-6", name: "iPad mini 8.3-inch (6th gen)",
             screenSize: CGSize(width: 1488, height: 2266), cornerRadius: 36),
        iPad(id: "ipad-10-2", name: "iPad 10.2-inch (9th gen)",
             screenSize: CGSize(width: 1620, height: 2160), cornerRadius: 0),
        iPad(id: "ipad-10-2-7-8", name: "iPad 10.2-inch (7th/8th gen)",
             screenSize: CGSize(width: 1620, height: 2160), cornerRadius: 0),
        iPad(id: "ipad-air-10-5-pro-10-5", name: "iPad Air 10.5-inch (3rd gen)",
             screenSize: CGSize(width: 1668, height: 2224), cornerRadius: 0),
        iPad(id: "ipad-pro-10-5", name: "iPad Pro 10.5-inch",
             screenSize: CGSize(width: 1668, height: 2224), cornerRadius: 0),
        iPad(id: "ipad-9-7-mini-retina", name: "iPad 9.7-inch (5th/6th gen)",
             screenSize: CGSize(width: 1536, height: 2048), cornerRadius: 0),
        iPad(id: "ipad-pro-9-7", name: "iPad Pro 9.7-inch",
             screenSize: CGSize(width: 1536, height: 2048), cornerRadius: 0),
        iPad(id: "ipad-air-2", name: "iPad Air 2",
             screenSize: CGSize(width: 1536, height: 2048), cornerRadius: 0),
        iPad(id: "ipad-mini-7-9", name: "iPad mini 7.9-inch (4th/5th gen)",
             screenSize: CGSize(width: 1536, height: 2048), cornerRadius: 0),
    ]

    // MARK: - Per-geometry constructors

    // Existing display corner radii came from the kylebshr/ScreenCorners table.
    // The 18 Pro, Air, 17e and 16e radii and scales were verified against Apple's
    // installed CoreSimulator device capabilities.plist: DeviceCornerRadius
    // (points) multiplied by main-screen-scale. These profiles intentionally
    // have no preset image geometry; imports derive it from the actual PNG.

    private static func iPhone(id: String,
                               name: String,
                               screenSize: CGSize,
                               cornerRadius: CGFloat,
                               cutout: DisplayCutout) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name, family: .iPhone,
            screenSize: screenSize,
            displayScale: 3,
            frameSize: screenSize,
            screenOffset: .zero,
            screenCornerRadius: cornerRadius,
            displayCutout: cutout
        )
    }

    // Frame sizes match Apple Design Resources canonical dimensions so
    // user-uploaded bezel PNGs from those packs match exactly. VideoToolbox
    // doesn't strictly require multiples of 16 — that's an optimization,
    // not a correctness issue, and breaks BYOB validation.

    private static func proMax(id: String, name: String, cutout: DisplayCutout) -> DeviceProfile {
        return DeviceProfile(
            id: id, displayName: name, family: .iPhone,
            screenSize: CGSize(width: 1320, height: 2868),
            displayScale: 3,
            frameSize: CGSize(width: 1470, height: 3000),
            screenOffset: CGPoint(x: 75, y: 66),
            screenCornerRadius: 186,
            displayCutout: cutout
        )
    }

    private static func proMax2796(id: String, name: String, cutout: DisplayCutout) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name, family: .iPhone,
            screenSize: CGSize(width: 1290, height: 2796),
            displayScale: 3,
            frameSize: CGSize(width: 1440, height: 2940),
            screenOffset: CGPoint(x: 75, y: 72),
            screenCornerRadius: 165,
            displayCutout: cutout
        )
    }

    private static func pro(id: String, name: String, cutout: DisplayCutout) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name, family: .iPhone,
            screenSize: CGSize(width: 1206, height: 2622),
            displayScale: 3,
            frameSize: CGSize(width: 1350, height: 2760),
            screenOffset: CGPoint(x: 72, y: 69),
            screenCornerRadius: 186,
            displayCutout: cutout
        )
    }

    private static func standard(id: String, name: String, cutout: DisplayCutout) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name, family: .iPhone,
            screenSize: CGSize(width: 1179, height: 2556),
            displayScale: 3,
            frameSize: CGSize(width: 1359, height: 2736),
            screenOffset: CGPoint(x: 90, y: 90),
            screenCornerRadius: 165,
            displayCutout: cutout
        )
    }

    private static func proMaxNotched(id: String, name: String, cutout: DisplayCutout) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name, family: .iPhone,
            screenSize: CGSize(width: 1284, height: 2778),
            displayScale: 3,
            frameSize: CGSize(width: 1410, height: 2904),
            screenOffset: CGPoint(x: 63, y: 63),
            screenCornerRadius: 160,
            displayCutout: cutout
        )
    }

    private static func standardNotched(id: String, name: String, cutout: DisplayCutout) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name, family: .iPhone,
            screenSize: CGSize(width: 1170, height: 2532),
            displayScale: 3,
            frameSize: CGSize(width: 1290, height: 2652),
            screenOffset: CGPoint(x: 60, y: 60),
            screenCornerRadius: 142,
            displayCutout: cutout
        )
    }

    private static func mini(id: String, name: String, cutout: DisplayCutout) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name, family: .iPhone,
            screenSize: CGSize(width: 1080, height: 2340),
            displayScale: 3,
            frameSize: CGSize(width: 1190, height: 2450),
            screenOffset: CGPoint(x: 55, y: 55),
            screenCornerRadius: 132,
            displayCutout: cutout
        )
    }

    private static func iPad(id: String,
                             name: String,
                             screenSize: CGSize,
                             cornerRadius: CGFloat) -> DeviceProfile {
        return DeviceProfile(
            id: id,
            displayName: name,
            family: .iPad,
            screenSize: screenSize,
            displayScale: 2,
            frameSize: screenSize,
            screenOffset: .zero,
            screenCornerRadius: cornerRadius,
            displayCutout: .none
        )
    }

    /// Match the captured feed resolution to a known iPhone or iPad profile.
    static func detect(for capturedSize: CGSize) -> DeviceProfile? {
        if let exact = catalog.first(where: { profile in
            abs(profile.screenSize.width - capturedSize.width) < 1
                && abs(profile.screenSize.height - capturedSize.height) < 1
        }) {
            return exact.withOrientation(landscape: capturedSize.width > capturedSize.height)
        }

        return catalog.first { profile in
            abs(profile.screenSize.width - capturedSize.height) < 1
                && abs(profile.screenSize.height - capturedSize.width) < 1
        }?.withOrientation(landscape: capturedSize.width > capturedSize.height)
    }

    func oriented(matching size: CGSize) -> DeviceProfile {
        let base = Self.catalog.first { $0.id == id } ?? self
        return base.withOrientation(landscape: size.width > size.height)
    }

    private func withOrientation(landscape: Bool) -> DeviceProfile {
        let orientedFrameSize = Self.oriented(frameSize, landscape: landscape)
        let orientedScreenSize = Self.oriented(screenSize, landscape: landscape)
        let orientedScreenOffset = landscape
            ? CGPoint(x: frameSize.height - screenOffset.y - orientedScreenSize.width,
                      y: screenOffset.x)
            : screenOffset

        return DeviceProfile(
            id: id,
            displayName: displayName,
            family: family,
            screenSize: orientedScreenSize,
            displayScale: displayScale,
            frameSize: family == .iPad ? orientedScreenSize : orientedFrameSize,
            screenOffset: family == .iPad ? .zero : orientedScreenOffset,
            screenCornerRadius: screenCornerRadius,
            displayCutout: displayCutout
        )
    }

    private static func oriented(_ size: CGSize, landscape: Bool) -> CGSize {
        let short = min(size.width, size.height)
        let long = max(size.width, size.height)
        return landscape
            ? CGSize(width: long, height: short)
            : CGSize(width: short, height: long)
    }
}
