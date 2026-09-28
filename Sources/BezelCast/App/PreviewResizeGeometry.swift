import CoreGraphics

struct PreviewResizeEdges: OptionSet, Sendable {
    let rawValue: Int

    static let left = Self(rawValue: 1 << 0)
    static let right = Self(rawValue: 1 << 1)
    static let top = Self(rawValue: 1 << 2)
    static let bottom = Self(rawValue: 1 << 3)
}

/// AppKit coordinates throughout: origins are at the bottom left and pointer
/// translations are measured in screen points, independently of a display.
enum PreviewResizeGeometry {
    static func edges(at point: CGPoint, around rect: CGRect,
                      hitWidth: CGFloat = 8, cornerWidth: CGFloat = 24) -> PreviewResizeEdges {
        guard valid(rect), point.x.isFinite, point.y.isFinite,
              hitWidth.isFinite, hitWidth > 0, cornerWidth.isFinite, cornerWidth >= 0,
              point.x >= rect.minX - hitWidth, point.x <= rect.maxX + hitWidth,
              point.y >= rect.minY - hitWidth, point.y <= rect.maxY + hitWidth else { return [] }

        let leftDistance = abs(point.x - rect.minX)
        let rightDistance = abs(point.x - rect.maxX)
        let bottomDistance = abs(point.y - rect.minY)
        let topDistance = abs(point.y - rect.maxY)
        let horizontal: PreviewResizeEdges = leftDistance <= rightDistance ? .left : .right
        let vertical: PreviewResizeEdges = bottomDistance <= topDistance ? .bottom : .top

        // The visible arc of a rounded phone corner lies inside its rectangular
        // bounds. Extend corner targets inward while leaving the center clear.
        let cornerDepth = min(max(hitWidth, cornerWidth), min(rect.width, rect.height) / 4)
        let inCornerX = point.x <= rect.minX + cornerDepth || point.x >= rect.maxX - cornerDepth
        let inCornerY = point.y <= rect.minY + cornerDepth || point.y >= rect.maxY - cornerDepth
        if inCornerX && inCornerY { return horizontal.union(vertical) }

        var result: PreviewResizeEdges = []
        if min(leftDistance, rightDistance) <= hitWidth { result.insert(horizontal) }
        if min(bottomDistance, topDistance) <= hitWidth { result.insert(vertical) }
        return result
    }

    /// Resize a fitted canvas without consuming existing letterboxing first.
    /// `previewRect` is the complete canvas in window coordinates. `handleRect`
    /// can identify a phone inside that canvas when a background is present.
    /// Each calculation uses the drag's starting rectangles and total pointer
    /// translation, so rounding and minimum-size clamping cannot accumulate.
    static func frame(startingWindowFrame: CGRect, previewRect: CGRect,
                      handleRect: CGRect? = nil, viewportSize: CGSize? = nil, edges: PreviewResizeEdges,
                      translation: CGPoint, minimumSize: CGSize) -> CGRect {
        let handle = handleRect ?? previewRect
        let viewport = viewportSize ?? previewRect.size
        // Rounding the short side of the native view by one point changes the
        // aspect-fitted long side by more than a point on tall or wide devices.
        let layoutTolerance: CGFloat = 1
        let allEdges: PreviewResizeEdges = [.left, .right, .top, .bottom]
        guard valid(startingWindowFrame), valid(previewRect), valid(handle),
              CGRect(origin: .zero, size: startingWindowFrame.size)
                .insetBy(dx: -0.001, dy: -0.001).contains(previewRect),
              previewRect.insetBy(dx: -0.001, dy: -0.001).contains(handle), !edges.isEmpty,
              edges.subtracting(allEdges).isEmpty,
              !(edges.contains(.left) && edges.contains(.right)),
              !(edges.contains(.top) && edges.contains(.bottom)),
              translation.x.isFinite, translation.y.isFinite,
              minimumSize.width.isFinite, minimumSize.height.isFinite,
              minimumSize.width >= 0, minimumSize.height >= 0,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0,
              viewport.width >= previewRect.width - layoutTolerance,
              viewport.height >= previewRect.height - layoutTolerance,
              viewport.width <= startingWindowFrame.width + layoutTolerance,
              viewport.height <= startingWindowFrame.height + layoutTolerance else { return startingWindowFrame }

        let horizontalSign: CGFloat = edges.contains(.right) ? 1 : (edges.contains(.left) ? -1 : 0)
        let verticalSign: CGFloat = edges.contains(.top) ? 1 : (edges.contains(.bottom) ? -1 : 0)
        let requestedScale: CGFloat
        if horizontalSign != 0 && verticalSign != 0 {
            // Project the pointer onto the aspect-constrained diagonal. The
            // closest possible corner follows mixed-axis drags without jumps.
            requestedScale = 1 + (translation.x * horizontalSign * handle.width
                + translation.y * verticalSign * handle.height)
                / (handle.width * handle.width + handle.height * handle.height)
        } else if horizontalSign != 0 {
            requestedScale = 1 + translation.x * horizontalSign / handle.width
        } else {
            requestedScale = 1 + translation.y * verticalSign / handle.height
        }

        let whitespace = CGSize(width: startingWindowFrame.width - previewRect.width,
                                height: startingWindowFrame.height - previewRect.height)
        // When one window dimension reaches its minimum, the canvas can keep
        // shrinking along the other axis. The clamped axis gains centered
        // letterboxing instead of making a portrait phone impossible to shrink.
        var constrainedScales: [CGFloat] = []
        // Existing letterboxing stays constant. The initially fitted axis
        // therefore remains the fit constraint; treating its letterboxed peer
        // as fixed chrome would allow a scale the actual viewport cannot show.
        let widthTolerance = max(layoutTolerance, previewRect.width / previewRect.height)
        let heightTolerance = max(layoutTolerance, previewRect.height / previewRect.width)
        // On an accepted fitted axis, use the pixel-aligned canvas dimension
        // as the viewport dimension so rounding cannot invent extra chrome.
        if abs(viewport.width - previewRect.width) <= widthTolerance {
            constrainedScales.append((minimumSize.width - whitespace.width) / previewRect.width)
        }
        if abs(viewport.height - previewRect.height) <= heightTolerance {
            constrainedScales.append((minimumSize.height - whitespace.height) / previewRect.height)
        }
        guard !constrainedScales.isEmpty else { return startingWindowFrame }
        let minimumScale = max(1 / min(previewRect.width, previewRect.height),
                               constrainedScales.min() ?? 0)
        let scale = max(minimumScale, requestedScale)
        guard scale.isFinite else { return startingWindowFrame }

        let idealSize = CGSize(width: whitespace.width + previewRect.width * scale,
                               height: whitespace.height + previewRect.height * scale)
        let clampedSize = CGSize(width: max(minimumSize.width, idealSize.width),
                                 height: max(minimumSize.height, idealSize.height))
        let additionalWhitespace = CGSize(width: clampedSize.width - idealSize.width,
                                           height: clampedSize.height - idealSize.height)

        // Opposite corners stay fixed. A single-edge drag instead fixes the
        // opposite edge's midpoint, growing the other axis around its center.
        let anchor = CGPoint(x: edges.contains(.left) ? handle.maxX
                                : (edges.contains(.right) ? handle.minX : handle.midX),
                             y: edges.contains(.bottom) ? handle.maxY
                                : (edges.contains(.top) ? handle.minY : handle.midY))
        let scaleChange = scale - 1
        let result = CGRect(
            x: startingWindowFrame.minX - (anchor.x - previewRect.minX) * scaleChange
                - additionalWhitespace.width / 2,
            y: startingWindowFrame.minY - (anchor.y - previewRect.minY) * scaleChange
                - additionalWhitespace.height / 2,
            width: clampedSize.width,
            height: clampedSize.height)
        return valid(result) ? result : startingWindowFrame
    }

    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
            && rect.maxX.isFinite && rect.maxY.isFinite
    }
}
