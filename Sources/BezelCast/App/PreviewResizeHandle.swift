import AppKit
import SwiftUI

/// An interaction layer only: it never enters the capture compositor.
struct PreviewResizeHandle: NSViewRepresentable {
    let canvasSize: CGSize
    let deviceRect: CGRect
    let viewportSize: CGSize

    func makeNSView(context: Context) -> PreviewResizeView {
        let view = PreviewResizeView()
        view.configure(canvasSize: canvasSize, deviceRect: deviceRect, viewportSize: viewportSize)
        return view
    }

    func updateNSView(_ view: PreviewResizeView, context: Context) {
        view.configure(canvasSize: canvasSize, deviceRect: deviceRect, viewportSize: viewportSize)
    }
}

final class PreviewResizeView: NSView {
    static let edgeInset: CGFloat = 8

    private var canvasSize: CGSize = .zero
    private var sourceDeviceRect: CGRect = .zero
    private var viewportSize: CGSize?
    private var edgeTrackingArea: NSTrackingArea?
    private var drag: ResizeDrag?

    private struct ResizeDrag {
        let windowFrame: CGRect
        let canvasRect: CGRect
        let handleRect: CGRect
        let viewportSize: CGSize
        let edges: PreviewResizeEdges
        let startLocation: CGPoint
        let minimumSize: CGSize
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(canvasSize: CGSize, deviceRect: CGRect, viewportSize: CGSize? = nil) {
        self.canvasSize = canvasSize
        sourceDeviceRect = deviceRect
        self.viewportSize = viewportSize
    }

    var canvasRect: CGRect {
        let available = bounds.insetBy(dx: Self.edgeInset, dy: Self.edgeInset)
        guard canvasSize.width > 0, canvasSize.height > 0,
              canvasSize.width.isFinite, canvasSize.height.isFinite,
              available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / canvasSize.width, available.height / canvasSize.height)
        let size = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        return CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    var deviceRectInView: CGRect {
        let canvas = canvasRect
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        let scale = canvas.width / canvasSize.width
        return CGRect(x: canvas.minX + sourceDeviceRect.minX * scale,
                      y: canvas.minY + sourceDeviceRect.minY * scale,
                      width: sourceDeviceRect.width * scale,
                      height: sourceDeviceRect.height * scale)
    }

    private var canResize: Bool {
        guard let window else { return false }
        return window.styleMask.contains(.resizable) && !window.styleMask.contains(.fullScreen)
    }

    private func handle(at point: CGPoint) -> (rect: CGRect, edges: PreviewResizeEdges)? {
        guard canResize else { return nil }
        // A background adds a second visible border. Both borders resize the
        // complete presentation, including the phone, at the same scale.
        for (index, rect) in [deviceRectInView, canvasRect].enumerated() {
            let cornerWidth = index == 0 ? max(24, min(rect.width, rect.height) * 0.075) : 24
            let edges = PreviewResizeGeometry.edges(at: point, around: rect, cornerWidth: cornerWidth)
            if !edges.isEmpty { return (rect, edges) }
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0,
              handle(at: convert(point, from: superview)) != nil else { return nil }
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let edgeTrackingArea { removeTrackingArea(edgeTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                 options: [.inVisibleRect, .activeAlways, .mouseMoved,
                                           .mouseEnteredAndExited, .cursorUpdate],
                                 owner: self, userInfo: nil)
        addTrackingArea(area)
        edgeTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { updateCursor(with: event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(with: event) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(with: event) }
    override func mouseExited(with event: NSEvent) {
        if drag == nil { NSCursor.arrow.set() }
    }

    private func updateCursor(with event: NSEvent) {
        if let drag {
            Self.cursor(for: drag.edges).set()
        } else if let handle = handle(at: convert(event.locationInWindow, from: nil)) {
            Self.cursor(for: handle.edges).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window,
              let handle = handle(at: convert(event.locationInWindow, from: nil)) else { return }
        let contentMinimum = window.frameRect(forContentRect: CGRect(origin: .zero,
                                                                     size: window.contentMinSize)).size
        drag = ResizeDrag(windowFrame: window.frame,
                          canvasRect: convert(canvasRect, to: nil),
                          handleRect: convert(handle.rect, to: nil),
                          viewportSize: viewportSize ?? canvasRect.size,
                          edges: handle.edges,
                          startLocation: window.convertPoint(toScreen: event.locationInWindow),
                          minimumSize: CGSize(width: max(window.minSize.width, contentMinimum.width),
                                              height: max(window.minSize.height, contentMinimum.height)))
        Self.cursor(for: handle.edges).set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let drag else { return }
        let location = window.convertPoint(toScreen: event.locationInWindow)
        let frame = PreviewResizeGeometry.frame(startingWindowFrame: drag.windowFrame,
                                                previewRect: drag.canvasRect,
                                                handleRect: drag.handleRect,
                                                viewportSize: drag.viewportSize,
                                                edges: drag.edges,
                                                translation: CGPoint(x: location.x - drag.startLocation.x,
                                                                     y: location.y - drag.startLocation.y),
                                                minimumSize: drag.minimumSize)
        window.setFrame(frame, display: true, animate: false)
        Self.cursor(for: drag.edges).set()
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        if let window, !window.frameAutosaveName.isEmpty {
            window.saveFrame(usingName: window.frameAutosaveName)
        }
        updateCursor(with: event)
    }

    private static func cursor(for edges: PreviewResizeEdges) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch edges {
            case [.top, .left]: position = .topLeft
            case [.top, .right]: position = .topRight
            case [.bottom, .left]: position = .bottomLeft
            case [.bottom, .right]: position = .bottomRight
            case .top: position = .top
            case .bottom: position = .bottom
            case .left: position = .left
            default: position = .right
            }
            return .frameResize(position: position, directions: .all)
        }
        if edges.contains(.left) || edges.contains(.right) {
            if edges.contains(.top) || edges.contains(.bottom) {
                return edges == [.top, .left] || edges == [.bottom, .right]
                    ? diagonalDownCursor : diagonalUpCursor
            }
            return .resizeLeftRight
        }
        return .resizeUpDown
    }

    // macOS 14 has no public diagonal frame cursors.
    private static let diagonalUpCursor = diagonalCursor(rising: true)
    private static let diagonalDownCursor = diagonalCursor(rising: false)

    private static func diagonalCursor(rising: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let path = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: x, y: rising ? y : 24 - y)
            }
            path.move(to: point(5, 5)); path.line(to: point(19, 19))
            path.move(to: point(5, 11)); path.line(to: point(5, 5)); path.line(to: point(11, 5))
            path.move(to: point(13, 19)); path.line(to: point(19, 19)); path.line(to: point(19, 13))
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.white.setStroke()
            path.lineWidth = 4
            path.stroke()
            NSColor.black.setStroke()
            path.lineWidth = 2
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }
}
