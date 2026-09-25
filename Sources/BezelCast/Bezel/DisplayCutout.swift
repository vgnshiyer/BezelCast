import CoreGraphics

/// A model's physical display interruption, independent of its screen size.
/// Shapes are original approximations; see Documentation/DeviceCutouts.md.
enum DisplayCutout: Equatable, Sendable {
    case none
    case wideNotch
    case notch
    case dynamicIsland
    case compactDynamicIsland

    /// Artwork uses portrait, top-left screen coordinates before rotation.
    func path(in screen: CGRect, displayScale: CGFloat) -> CGPath? {
        switch self {
        case .none:
            return nil
        case .wideNotch:
            return notch(in: screen, scale: displayScale, width: 210, height: 30)
        case .notch:
            return notch(in: screen, scale: displayScale, width: 160, height: 34)
        case .dynamicIsland, .compactDynamicIsland:
            let width: CGFloat = self == .compactDynamicIsland ? 80 : 100
            let height: CGFloat = self == .compactDynamicIsland ? 25 : 28
            let rect = CGRect(x: screen.midX - width * displayScale / 2,
                              y: screen.minY + (32 / 3) * displayScale,
                              width: width * displayScale, height: height * displayScale)
            return CGPath(roundedRect: rect, cornerWidth: rect.height / 2,
                          cornerHeight: rect.height / 2, transform: nil)
        }
    }

    private func notch(in screen: CGRect, scale: CGFloat,
                       width: CGFloat, height: CGFloat) -> CGPath {
        let left = screen.midX - width * scale / 2
        let right = screen.midX + width * scale / 2
        let top = screen.minY
        let bottom = top + height * scale
        let shoulder = 6 * scale
        let corner = 10 * scale
        let curve: CGFloat = 0.5522847498
        let path = CGMutablePath()

        // Extend into the top rail so antialiasing cannot leave a hairline gap.
        // Concave shoulders join the rail; only the bottom corners round inward.
        path.move(to: CGPoint(x: left - shoulder, y: top - scale))
        path.addLine(to: CGPoint(x: right + shoulder, y: top - scale))
        path.addLine(to: CGPoint(x: right + shoulder, y: top))
        path.addCurve(to: CGPoint(x: right, y: top + shoulder),
                      control1: CGPoint(x: right + shoulder * (1 - curve), y: top),
                      control2: CGPoint(x: right, y: top + shoulder * (1 - curve)))
        path.addLine(to: CGPoint(x: right, y: bottom - corner))
        path.addCurve(to: CGPoint(x: right - corner, y: bottom),
                      control1: CGPoint(x: right, y: bottom - corner * (1 - curve)),
                      control2: CGPoint(x: right - corner * (1 - curve), y: bottom))
        path.addLine(to: CGPoint(x: left + corner, y: bottom))
        path.addCurve(to: CGPoint(x: left, y: bottom - corner),
                      control1: CGPoint(x: left + corner * (1 - curve), y: bottom),
                      control2: CGPoint(x: left, y: bottom - corner * (1 - curve)))
        path.addLine(to: CGPoint(x: left, y: top + shoulder))
        path.addCurve(to: CGPoint(x: left - shoulder, y: top),
                      control1: CGPoint(x: left, y: top + shoulder * (1 - curve)),
                      control2: CGPoint(x: left - shoulder * (1 - curve), y: top))
        path.closeSubpath()
        return path
    }
}
