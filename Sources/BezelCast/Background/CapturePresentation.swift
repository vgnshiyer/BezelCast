import CoreGraphics
import Foundation

enum BackgroundCanvas: String, CaseIterable, Identifiable, Codable, Sendable {
    case landscape
    case portrait
    case square

    var id: String { rawValue }

    var name: String {
        switch self {
        case .landscape: "Landscape"
        case .portrait: "Portrait"
        case .square: "Square"
        }
    }

    var size: CGSize {
        switch self {
        case .landscape: CGSize(width: 1920, height: 1080)
        case .portrait: CGSize(width: 1080, height: 1920)
        case .square: CGSize(width: 1440, height: 1440)
        }
    }
}

struct CapturePresentation: Sendable {
    var background: CaptureBackground
    var canvas: BackgroundCanvas
    var padding: CGFloat
    var shadow: Bool
    var fixedCanvasSize: CGSize?
    var previousBackground: CaptureBackground?
    var transitionStartTime: TimeInterval?

    init(background: CaptureBackground = .none,
         canvas: BackgroundCanvas = .landscape,
         padding: CGFloat = 0.12,
         shadow: Bool = true,
         fixedCanvasSize: CGSize? = nil,
         previousBackground: CaptureBackground? = nil,
         transitionStartTime: TimeInterval? = nil) {
        self.background = background
        self.canvas = canvas
        self.padding = padding
        self.shadow = shadow
        self.fixedCanvasSize = fixedCanvasSize
        self.previousBackground = previousBackground
        self.transitionStartTime = transitionStartTime
    }

    func outputSize(for deviceSize: CGSize) -> CGSize {
        if let fixedCanvasSize, fixedCanvasSize.width.isFinite, fixedCanvasSize.height.isFinite,
           fixedCanvasSize.width > 0, fixedCanvasSize.height > 0 {
            return fixedCanvasSize
        }
        return background.isNone ? deviceSize : canvas.size
    }

    /// The same fit is used by previews, screenshots, and every movie frame.
    /// None preserves native output unless a recording has already fixed its canvas.
    func deviceRect(for deviceSize: CGSize) -> CGRect {
        let outputSize = outputSize(for: deviceSize)
        guard deviceSize.width > 0, deviceSize.height > 0,
              deviceSize.width.isFinite, deviceSize.height.isFinite else { return .zero }
        let inset = background.isNone ? 0 : min(outputSize.width, outputSize.height)
            * (padding.isFinite ? min(0.3, max(0, padding)) : 0.12)
        let available = CGRect(origin: .zero, size: outputSize).insetBy(dx: inset, dy: inset)
        let scale = min(available.width / deviceSize.width, available.height / deviceSize.height)
        let size = CGSize(width: deviceSize.width * scale, height: deviceSize.height * scale)
        return CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    var backgroundTransitionProgress: Double {
        guard previousBackground != nil, let transitionStartTime else { return 1 }
        return min(1, max(0, (ProcessInfo.processInfo.systemUptime - transitionStartTime) / 0.22))
    }
}
