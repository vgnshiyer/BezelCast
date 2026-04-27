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
}

extension DeviceProfile {
    /// Catalog of recognized devices. Multiple models can share the same
    /// resolution (and therefore the same bezel art) — they're all listed
    /// explicitly so the UI can show the correct model name. detect(for:)
    /// returns the first match in catalog order, so newest models are listed
    /// first per resolution group.
    static let catalog: [DeviceProfile] = [
        // 1320×2868 — iPhone 16/17 Pro Max (Dynamic Island)
        proMax(id: "iphone-17-pro-max",  name: "iPhone 17 Pro Max"),
        proMax(id: "iphone-16-pro-max",  name: "iPhone 16 Pro Max"),

        // 1290×2796 — Dynamic Island Pro Max + Plus models (14/15 Pro Max, 14/15/16 Plus)
        proMax2796(id: "iphone-16-plus",      name: "iPhone 16 Plus"),
        proMax2796(id: "iphone-15-pro-max",   name: "iPhone 15 Pro Max"),
        proMax2796(id: "iphone-15-plus",      name: "iPhone 15 Plus"),
        proMax2796(id: "iphone-14-pro-max",   name: "iPhone 14 Pro Max"),
        // 1290×2796 with notch — iPhone 14 Plus
        proMax2796Notched(id: "iphone-14-plus", name: "iPhone 14 Plus"),

        // 1206×2622 — iPhone 16/17 Pro (Dynamic Island)
        pro(id: "iphone-17-pro", name: "iPhone 17 Pro"),
        pro(id: "iphone-16-pro", name: "iPhone 16 Pro"),

        // 1179×2556 — Dynamic Island standard / Pro (14 Pro, 15, 15 Pro, 16, 17)
        standard(id: "iphone-17",     name: "iPhone 17"),
        standard(id: "iphone-16",     name: "iPhone 16"),
        standard(id: "iphone-15-pro", name: "iPhone 15 Pro"),
        standard(id: "iphone-15",     name: "iPhone 15"),
        standard(id: "iphone-14-pro", name: "iPhone 14 Pro"),

        // 1284×2778 — iPhone 12/13 Pro Max (notched)
        proMaxNotched(id: "iphone-13-pro-max", name: "iPhone 13 Pro Max"),
        proMaxNotched(id: "iphone-12-pro-max", name: "iPhone 12 Pro Max"),

        // 1170×2532 — iPhone 12/13/14 standard, 12/13 Pro (notched)
        standardNotched(id: "iphone-14",     name: "iPhone 14"),
        standardNotched(id: "iphone-13-pro", name: "iPhone 13 Pro"),
        standardNotched(id: "iphone-13",     name: "iPhone 13"),
        standardNotched(id: "iphone-12-pro", name: "iPhone 12 Pro"),
        standardNotched(id: "iphone-12",     name: "iPhone 12"),

        // 1080×2340 — iPhone 12/13 mini (notched)
        mini(id: "iphone-13-mini", name: "iPhone 13 mini"),
        mini(id: "iphone-12-mini", name: "iPhone 12 mini"),

        // 750×1334 — iPhone SE (3rd gen) — home button, no rounded screen
        DeviceProfile(
            id: "iphone-se",
            displayName: "iPhone SE",
            screenSize: CGSize(width: 750, height: 1334),
            frameSize: CGSize(width: 870, height: 1454),
            screenOffset: CGPoint(x: 60, y: 60),
            screenCornerRadius: 0,
            island: nil
        ),
    ]

    // MARK: - Per-geometry constructors (avoid copy-paste across same-resolution models)

    private static func proMax(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1320, height: 2868),
            frameSize: CGSize(width: 1470, height: 3000),
            screenOffset: CGPoint(x: 75, y: 66),
            screenCornerRadius: 180,
            island: CGRect(x: 470, y: 100, width: 380, height: 115)
        )
    }

    private static func proMax2796(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1290, height: 2796),
            frameSize: CGSize(width: 1440, height: 2940),
            screenOffset: CGPoint(x: 75, y: 72),
            screenCornerRadius: 175,
            island: CGRect(x: 455, y: 95, width: 380, height: 115)
        )
    }

    private static func proMax2796Notched(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1290, height: 2796),
            frameSize: CGSize(width: 1440, height: 2940),
            screenOffset: CGPoint(x: 75, y: 72),
            screenCornerRadius: 175,
            island: nil
        )
    }

    private static func pro(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1206, height: 2622),
            frameSize: CGSize(width: 1350, height: 2760),
            screenOffset: CGPoint(x: 72, y: 69),
            screenCornerRadius: 165,
            island: CGRect(x: 415, y: 95, width: 376, height: 110)
        )
    }

    private static func standard(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1179, height: 2556),
            frameSize: CGSize(width: 1359, height: 2736),
            screenOffset: CGPoint(x: 90, y: 90),
            screenCornerRadius: 162,
            island: CGRect(x: 410, y: 95, width: 360, height: 105)
        )
    }

    private static func proMaxNotched(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1284, height: 2778),
            frameSize: CGSize(width: 1410, height: 2904),
            screenOffset: CGPoint(x: 63, y: 63),
            screenCornerRadius: 165,
            island: nil
        )
    }

    private static func standardNotched(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1170, height: 2532),
            frameSize: CGSize(width: 1290, height: 2652),
            screenOffset: CGPoint(x: 60, y: 60),
            screenCornerRadius: 155,
            island: nil
        )
    }

    private static func mini(id: String, name: String) -> DeviceProfile {
        DeviceProfile(
            id: id, displayName: name,
            screenSize: CGSize(width: 1080, height: 2340),
            frameSize: CGSize(width: 1190, height: 2450),
            screenOffset: CGPoint(x: 55, y: 55),
            screenCornerRadius: 145,
            island: nil
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
    /// all around, screen corner radius 14% of width, no island.
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
            island: nil
        )
    }
}

/// Programmatic bezel art constants. Plain black, thin ring against the screen.
enum DefaultBezelArt {
    /// Bezel ring thickness in screen-pixel units (added on every side around the screen).
    static let thickness: CGFloat = 36
    /// Inset applied to the bezel's inner hole so it overlaps the screen edge by
    /// a sliver, masking the anti-aliasing gap between the two rounded shapes.
    static let edgeOverlap: CGFloat = 1.5
    static let color = NSColor.black
}
