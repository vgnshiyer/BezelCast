import CoreGraphics

enum DeviceDisplayLayout {
    /// Fit the complete device into the space the user chose. Native pixel
    /// dimensions determine proportions, never the preview's apparent size.
    static func previewSize(for profile: DeviceProfile,
                            customFrame: CustomFrame?,
                            presentation: CapturePresentation = .init(),
                            fitting availableSize: CGSize) -> CGSize {
        let canvas = presentation.outputSize(for: customFrame?.geometry.frameSize ?? profile.screenSize)
        guard canvas.width.isFinite, canvas.height.isFinite,
              availableSize.width.isFinite, availableSize.height.isFinite,
              canvas.width > 0, canvas.height > 0,
              availableSize.width > 0, availableSize.height > 0 else { return .zero }

        let scale = min(availableSize.width / canvas.width,
                        availableSize.height / canvas.height)
        return CGSize(width: canvas.width * scale, height: canvas.height * scale)
    }
}
