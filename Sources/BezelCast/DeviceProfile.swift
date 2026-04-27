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
    /// Catalog of recognized devices, hard-coded. Detection picks the entry
    /// whose screenSize matches the captured feed.
    static let catalog: [DeviceProfile] = [
        DeviceProfile(
            id: "iphone-17-pro-max",
            displayName: "iPhone 17 Pro Max",
            screenSize: CGSize(width: 1320, height: 2868),
            frameSize: CGSize(width: 1470, height: 3000),
            screenOffset: CGPoint(x: 75, y: 66),
            screenCornerRadius: 180,
            island: CGRect(x: 470, y: 100, width: 380, height: 115)
        ),
        DeviceProfile(
            id: "iphone-15-pro-max",
            displayName: "iPhone 15 Pro Max",
            screenSize: CGSize(width: 1290, height: 2796),
            frameSize: CGSize(width: 1440, height: 2940),
            screenOffset: CGPoint(x: 75, y: 72),
            screenCornerRadius: 175,
            island: CGRect(x: 455, y: 95, width: 380, height: 115)
        ),
        DeviceProfile(
            id: "iphone-17-pro",
            displayName: "iPhone 17 Pro",
            screenSize: CGSize(width: 1206, height: 2622),
            frameSize: CGSize(width: 1350, height: 2760),
            screenOffset: CGPoint(x: 72, y: 69),
            screenCornerRadius: 165,
            island: CGRect(x: 415, y: 95, width: 376, height: 110)
        ),
        DeviceProfile(
            id: "iphone-17",
            displayName: "iPhone 17",
            screenSize: CGSize(width: 1179, height: 2556),
            frameSize: CGSize(width: 1359, height: 2736),
            screenOffset: CGPoint(x: 90, y: 90),
            screenCornerRadius: 162,
            island: CGRect(x: 410, y: 95, width: 360, height: 105)
        ),
    ]

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
