import AppKit

struct DeviceProfile: Equatable {
    let id: String
    let displayName: String

    /// iPhone screen pixel resolution. Used for matching against the captured feed.
    let screenSize: CGSize
    /// Bezel canvas dimensions. Output size of screenshots / recordings.
    let frameSize: CGSize
    /// Top-left of the screen within the frame, image-data coords (y from top).
    let screenOffset: CGPoint
    /// Screen corner radius in screen-pixel units.
    let screenCornerRadius: CGFloat
    /// Dynamic Island position in screen-coord space (relative to screenOffset). nil if none.
    let island: CGRect?
    /// Notch size (width × height) in screen-pixel units. Always centered
    /// horizontally and attached to the top edge of the screen, so position is
    /// implicit. nil for non-notched models (DI models or SE).
    let notch: CGSize?

    var aspectRatio: CGFloat { screenSize.width / screenSize.height }

    /// Profiles whose aspect ratio is within `tolerance` of `reference`. Used
    /// to filter the picker — rendering an iPhone SE feed inside an iPhone Pro
    /// bezel (or vice versa) stretches the screen content unusably, so those
    /// combinations are hidden.
    static func compatible(with reference: DeviceProfile,
                           tolerance: CGFloat = 0.05) -> [DeviceProfile] {
        let target = reference.aspectRatio
        return catalog.filter { abs($0.aspectRatio - target) < tolerance }
    }

    /// Largest `frameSize` in the catalog — used as the reference for relative
    /// sizing in the live preview so smaller devices render smaller.
    static let largestFrameSize: CGSize = {
        let w = catalog.map(\.frameSize.width).max() ?? 0
        let h = catalog.map(\.frameSize.height).max() ?? 0
        return CGSize(width: w, height: h)
    }()
}

extension DeviceProfile {
    /// Apple's two notch sizes in screen-pixel units (@3x). The iPhone 12
    /// generation has the original "big notch" (210pt × 31pt). Apple shrank
    /// it for the iPhone 13 generation and kept that smaller size on every
    /// non-DI model after (13/13 Pro/13 Pro Max, 14, 14 Plus).
    private static let bigNotch = CGSize(width: 627, height: 93)
    private static let smallNotch = CGSize(width: 484, height: 93)

    /// Catalog of recognized devices. Multiple models can share the same
    /// resolution (and therefore the same bezel art) — they're all listed
    /// explicitly so the UI can show the correct model name. detect(for:)
    /// returns the first match in catalog order, so newest models are listed
    /// first per resolution group.
    static let catalog: [DeviceProfile] = [
        // 1320×2868 — iPhone 16/17 Pro Max (Dynamic Island)
        proMax(id: "iphone-17-pro-max",  name: "iPhone 17 Pro Max"),
        proMax(id: "iphone-16-pro-max",  name: "iPhone 16 Pro Max"),

        // 1290×2796 — Dynamic Island Pro Max + Plus models (14/15 Pro Max, 15/16 Plus)
        proMax2796(id: "iphone-16-plus",      name: "iPhone 16 Plus"),
        proMax2796(id: "iphone-15-pro-max",   name: "iPhone 15 Pro Max"),
        proMax2796(id: "iphone-15-plus",      name: "iPhone 15 Plus"),
        proMax2796(id: "iphone-14-pro-max",   name: "iPhone 14 Pro Max"),

        // 1206×2622 — iPhone 16/17 Pro (Dynamic Island)
        pro(id: "iphone-17-pro", name: "iPhone 17 Pro"),
        pro(id: "iphone-16-pro", name: "iPhone 16 Pro"),

        // 1179×2556 — Dynamic Island standard / Pro (14 Pro, 15, 15 Pro, 16, 17)
        standard(id: "iphone-17",     name: "iPhone 17"),
        standard(id: "iphone-16",     name: "iPhone 16"),
        standard(id: "iphone-15-pro", name: "iPhone 15 Pro"),
        standard(id: "iphone-15",     name: "iPhone 15"),
        standard(id: "iphone-14-pro", name: "iPhone 14 Pro"),

        // 1284×2778 — iPhone 12/13 Pro Max + 14 Plus (notched). iPhone 14 Plus
        // shares the 12/13 Pro Max chassis & resolution — Apple bumped to a
        // Dynamic Island only on the Pro Max line that year.
        proMaxNotched(id: "iphone-13-pro-max", name: "iPhone 13 Pro Max", notch: smallNotch),
        proMaxNotched(id: "iphone-12-pro-max", name: "iPhone 12 Pro Max", notch: bigNotch),
        proMaxNotched(id: "iphone-14-plus",   name: "iPhone 14 Plus",    notch: smallNotch),

        // 1170×2532 — iPhone 12/13/14 standard, 12/13 Pro (notched)
        standardNotched(id: "iphone-14",     name: "iPhone 14",     notch: smallNotch),
        standardNotched(id: "iphone-13-pro", name: "iPhone 13 Pro", notch: smallNotch),
        standardNotched(id: "iphone-13",     name: "iPhone 13",     notch: smallNotch),
        standardNotched(id: "iphone-12-pro", name: "iPhone 12 Pro", notch: bigNotch),
        standardNotched(id: "iphone-12",     name: "iPhone 12",     notch: bigNotch),

        // 1080×2340 — iPhone 12/13 mini (notched)
        mini(id: "iphone-13-mini", name: "iPhone 13 mini", notch: smallNotch),
        mini(id: "iphone-12-mini", name: "iPhone 12 mini", notch: bigNotch),

        // 750×1334 — iPhone SE (3rd gen) — home button, no rounded screen
        DeviceProfile(
            id: "iphone-se",
            displayName: "iPhone SE",
            screenSize: CGSize(width: 750, height: 1334),
            frameSize: CGSize(width: 870, height: 1454),
            screenOffset: CGPoint(x: 60, y: 60),
            screenCornerRadius: 0,
            island: nil,
            notch: nil
        ),
    ]

    // MARK: - Per-geometry constructors (avoid copy-paste across same-resolution models)

    // Apple's display corner radii and Dynamic Island specs per the iOS HIG
    // (display corner is in points; multiply by 3 for the @3x device pixel
    // value the renderer uses). The Dynamic Island is 125pt × 37.33pt
    // (375×112 px) sitting 11pt (33 px) below the top of the screen,
    // centered horizontally — same physical size on every model that has it.

    private static func proMax(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1320, height: 2868),
            frameSize: CGSize(width: 1470, height: 3000),
            screenOffset: CGPoint(x: 75, y: 66),
            screenCornerRadius: 186,
            island: CGRect(x: 473, y: 33, width: 375, height: 112),
            notch: nil
        )
    }

    private static func proMax2796(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1290, height: 2796),
            frameSize: CGSize(width: 1440, height: 2940),
            screenOffset: CGPoint(x: 75, y: 72),
            screenCornerRadius: 165,
            island: CGRect(x: 458, y: 33, width: 375, height: 112),
            notch: nil
        )
    }

    private static func pro(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1206, height: 2622),
            frameSize: CGSize(width: 1350, height: 2760),
            screenOffset: CGPoint(x: 72, y: 69),
            screenCornerRadius: 186,
            island: CGRect(x: 416, y: 33, width: 375, height: 112),
            notch: nil
        )
    }

    private static func standard(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1179, height: 2556),
            frameSize: CGSize(width: 1359, height: 2736),
            screenOffset: CGPoint(x: 90, y: 90),
            screenCornerRadius: 165,
            island: CGRect(x: 402, y: 33, width: 375, height: 112),
            notch: nil
        )
    }

    private static func proMaxNotched(id: String, name: String, notch: CGSize) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1284, height: 2778),
            frameSize: CGSize(width: 1410, height: 2904),
            screenOffset: CGPoint(x: 63, y: 63),
            screenCornerRadius: 160,
            island: nil,
            notch: notch
        )
    }

    private static func standardNotched(id: String, name: String, notch: CGSize) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1170, height: 2532),
            frameSize: CGSize(width: 1290, height: 2652),
            screenOffset: CGPoint(x: 60, y: 60),
            screenCornerRadius: 142,
            island: nil,
            notch: notch
        )
    }

    private static func mini(id: String, name: String, notch: CGSize) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1080, height: 2340),
            frameSize: CGSize(width: 1190, height: 2450),
            screenOffset: CGPoint(x: 55, y: 55),
            screenCornerRadius: 132,
            island: nil,
            notch: notch
        )
    }

    /// Match the captured feed resolution to a known profile. Tries portrait
    /// first, then landscape (returns nil for landscape since we only support
    /// portrait for now).
    static func detect(for capturedSize: CGSize) -> DeviceProfile? {
        catalog.first { profile in
            abs(profile.screenSize.width - capturedSize.width) < 1
                && abs(profile.screenSize.height - capturedSize.height) < 1
        }
    }

    /// Synthesize a profile for an unrecognized device. Default 5.5% margin
    /// all around, screen corner radius 14% of width, no island, no notch.
    static func generic(for capturedSize: CGSize) -> DeviceProfile {
        let margin = capturedSize.width * 0.055
        let frame = CGSize(width: capturedSize.width + margin * 2,
                           height: capturedSize.height + margin * 2)
        return DeviceProfile(
            id: "generic-\(Int(capturedSize.width))x\(Int(capturedSize.height))",
            displayName: "Connected Device",
            screenSize: capturedSize,
            frameSize: frame,
            screenOffset: CGPoint(x: margin, y: margin),
            screenCornerRadius: capturedSize.width * 0.14,
            island: nil,
            notch: nil
        )
    }
}

/// Programmatic bezel art constants. Plain black, thin ring against the screen.
enum DefaultBezelArt {
    /// Bezel ring thickness in screen-pixel units (added on every side around the screen).
    static let thickness: CGFloat = 36
    /// Inset applied to the bezel's inner hole so it overlaps the screen edge by
    /// a sliver, masking the anti-aliasing gap between the two rounded shapes.
    /// 3 px is enough to hide AA seams reliably across all profiles without
    /// visibly eating into the screen content.
    static let edgeOverlap: CGFloat = 3
    static let color = NSColor.black
}
