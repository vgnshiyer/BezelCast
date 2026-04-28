import CoreGraphics

enum DeviceDisplayLayout {
    private static let chromePadding = CGSize(width: 32, height: 96)
    private static let minimumWindowSize = CGSize(width: 360, height: 360)
    private static let largestIPhonePreviewHeight: CGFloat = 724

    private static var pointScale: CGFloat {
        let largestIPhone = DeviceProfile.largestDisplaySize(
            for: .iPhone,
            matching: CGSize(width: 1, height: 2)
        )
        let longSide = max(largestIPhone.width, largestIPhone.height)
        guard longSide > 0 else { return 1 }
        return largestIPhonePreviewHeight / longSide
    }

    static func previewSize(for profile: DeviceProfile,
                            customFrame: CustomFrame?) -> CGSize {
        displaySize(for: profile, customFrame: customFrame).scaled(by: pointScale)
    }

    static func windowSize(for profile: DeviceProfile,
                           customFrame: CustomFrame?) -> CGSize {
        let previewSize = previewSize(for: profile, customFrame: customFrame)
        return CGSize(width: max(minimumWindowSize.width, previewSize.width + chromePadding.width),
                      height: max(minimumWindowSize.height, previewSize.height + chromePadding.height))
    }

    private static func displaySize(for profile: DeviceProfile,
                                    customFrame: CustomFrame?) -> CGSize {
        guard let customFrame else { return profile.displaySize }

        if profile.hasPresetFrameGeometry {
            let frameSize = customFrame.geometry.frameSize.scaled(by: 1 / profile.displayScale)
            return frameSize.fitted(in: profile.displaySize)
        }

        let geometry = customFrame.geometry
        let screenRect = geometry.screenRect
        guard screenRect.width > 0, screenRect.height > 0 else {
            return profile.displaySize
        }

        let scale = min(profile.displaySize.width / screenRect.width,
                        profile.displaySize.height / screenRect.height)
        let frameSize = geometry.frameSize.scaled(by: scale)
        return frameSize.fitted(in: profile.displaySize)
    }
}

private extension CGSize {
    func scaled(by scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }

    func fitted(in boundingSize: CGSize) -> CGSize {
        guard width > 0, height > 0 else { return self }
        let scale = min(1,
                        boundingSize.width / width,
                        boundingSize.height / height)
        return scaled(by: scale)
    }
}
