import CoreGraphics
import XCTest
@testable import BezelCast

final class PreviewResizeGeometryTests: XCTestCase {
    private let window = CGRect(x: 100, y: 200, width: 500, height: 800)
    private let preview = CGRect(x: 40, y: 120, width: 360, height: 600)
    private let minimum = CGSize(width: 360, height: 360)

    func testSideDragsScaleBothDimensionsAndAnchorTheOppositeEdgeMidpoint() {
        let cases: [(PreviewResizeEdges, CGPoint, CGPoint)] = [
            (.right, CGPoint(x: 90, y: 400), CGPoint(x: 100, y: 125)),
            (.left, CGPoint(x: -90, y: -400), CGPoint(x: 10, y: 125)),
            (.top, CGPoint(x: 400, y: 150), CGPoint(x: 55, y: 200)),
            (.bottom, CGPoint(x: -400, y: -150), CGPoint(x: 55, y: 50))
        ]
        for (edges, translation, origin) in cases {
            let result = resize(edges, by: translation)
            assertRect(result, CGRect(origin: origin, size: CGSize(width: 590, height: 950)))
            let canvas = resizedPreview(in: result)
            XCTAssertEqual(canvas.width / canvas.height, preview.width / preview.height, accuracy: 0.0001)
            XCTAssertEqual(result.width - canvas.width, window.width - preview.width, accuracy: 0.0001)
            XCTAssertEqual(result.height - canvas.height, window.height - preview.height, accuracy: 0.0001)
        }
    }

    func testCornerDragsKeepTheOppositeVisibleCornerStationary() {
        let cases: [(PreviewResizeEdges, CGPoint, CGPoint)] = [
            ([.right, .top], CGPoint(x: 90, y: 150), CGPoint(x: 100, y: 200)),
            ([.right, .bottom], CGPoint(x: 90, y: -150), CGPoint(x: 100, y: 50)),
            ([.left, .top], CGPoint(x: -90, y: 150), CGPoint(x: 10, y: 200)),
            ([.left, .bottom], CGPoint(x: -90, y: -150), CGPoint(x: 10, y: 50))
        ]
        for (edges, translation, origin) in cases {
            assertRect(resize(edges, by: translation),
                       CGRect(origin: origin, size: CGSize(width: 590, height: 950)))
        }
    }

    func testCornerMovementProjectsSmoothlyOntoTheFixedAspectRatio() {
        let translation = CGPoint(x: 90, y: 0)
        let result = resize([.right, .top], by: translation)
        let newPreview = resizedPreview(in: result)
        let actualDelta = CGPoint(x: newPreview.width - preview.width,
                                  y: newPreview.height - preview.height)
        // The residual pointer distance is perpendicular to the permitted
        // diagonal, so this is the closest aspect-preserving corner position.
        let residual = CGPoint(x: translation.x - actualDelta.x, y: translation.y - actualDelta.y)
        XCTAssertEqual(residual.x * preview.width + residual.y * preview.height, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(actualDelta.x, 0)
        XCTAssertGreaterThan(actualDelta.y, 0)
        XCTAssertEqual(result.origin, window.origin)
    }

    func testShrinkingClampsToBothMinimumDimensionsWithoutChangingAspectOrAnchor() {
        let result = resize([.left, .bottom], by: CGPoint(x: 10_000, y: 10_000))
        XCTAssertEqual(result.width, 360, accuracy: 0.0001)
        XCTAssertEqual(result.height, 360, accuracy: 0.0001)
        let canvas = resizedPreview(in: result)
        XCTAssertEqual(canvas.width / canvas.height, preview.width / preview.height, accuracy: 0.0001)
        XCTAssertEqual(result.minX + canvas.maxX, window.minX + preview.maxX, accuracy: 0.0001)
        XCTAssertEqual(result.minY + canvas.maxY, window.minY + preview.maxY, accuracy: 0.0001)

        // The calculation always starts at mouse-down geometry, so moving
        // back from the clamp does not introduce accumulated drag dead zones.
        assertRect(resize(.left, by: .zero), window)
    }

    func testMinimumWidthStillAllowsThePortraitPhoneToShrink() {
        let result = resize(.right, by: CGPoint(x: -180, y: 0))
        assertRect(result, CGRect(x: 80, y: 350, width: 360, height: 500))
        let canvas = resizedPreview(in: result)
        XCTAssertEqual(canvas.size, CGSize(width: 180, height: 300))
        XCTAssertEqual(result.minX + canvas.minX, window.minX + preview.minX, accuracy: 0.0001)
        XCTAssertEqual(result.minY + canvas.midY, window.minY + preview.midY, accuracy: 0.0001)
    }

    func testMinimumHeightStillAllowsTheLandscapePreviewToShrink() {
        let result = PreviewResizeGeometry.frame(
            startingWindowFrame: CGRect(x: 100, y: 200, width: 900, height: 500),
            previewRect: CGRect(x: 50, y: 80, width: 800, height: 300),
            edges: .top, translation: CGPoint(x: 0, y: -150), minimumSize: minimum)
        assertRect(result, CGRect(x: 300, y: 195, width: 500, height: 360))
    }

    func testShrinkingCanBeLimitedByMinimumHeight() {
        let result = PreviewResizeGeometry.frame(startingWindowFrame: window, previewRect: preview,
            edges: .bottom, translation: CGPoint(x: 0, y: 10_000),
            minimumSize: CGSize(width: 450, height: 700))
        XCTAssertEqual(result.height, 700, accuracy: 0.0001)
        XCTAssertEqual(result.width, 450, accuracy: 0.0001)
        XCTAssertEqual(result.maxY, window.maxY, accuracy: 0.0001)
    }

    func testActualViewportMinimumPreventsAnImpossibleScaleInsideExistingLetterboxing() {
        let start = CGRect(x: 100, y: 200, width: 500, height: 500)
        let canvas = CGRect(x: 160, y: 16, width: 180, height: 404)
        let viewport = CGSize(width: 468, height: 404)
        let result = PreviewResizeGeometry.frame(startingWindowFrame: start, previewRect: canvas,
            viewportSize: viewport, edges: .right, translation: CGPoint(x: -1000, y: 0), minimumSize: minimum)
        let expectedScale: CGFloat = 264 / 404
        let actualScale = min((result.width - 32) / canvas.width, (result.height - 96) / canvas.height)
        XCTAssertEqual(actualScale, expectedScale, accuracy: 0.0001)
        XCTAssertEqual(result.width, 320 + 180 * expectedScale, accuracy: 0.0001)
        XCTAssertEqual(result.height, 360, accuracy: 0.0001)
        XCTAssertEqual(result.minX + canvas.minX, start.minX + canvas.minX, accuracy: 0.0001)
        XCTAssertEqual(result.minY + canvas.minY + canvas.height * actualScale / 2,
                       start.minY + canvas.midY, accuracy: 0.0001)
    }

    func testPixelRoundingOfTheShortSideDoesNotDisableTallOrWidePreviewDragging() {
        // A 220.65pt phone view rounds to 220pt on a non-Retina display. Its
        // fitted image is then 1.36pt shorter than the proposed viewport.
        for landscape in [false, true] {
            let size = landscape ? CGSize(width: 460, height: 420) : CGSize(width: 420, height: 460)
            let canvas = landscape
                ? CGRect(x: 0.677966, y: 100, width: 458.644068, height: 220)
                : CGRect(x: 100, y: 0.677966, width: 220, height: 458.644068)
            let start = CGRect(x: 100, y: 200, width: size.width, height: size.height)
            let result = PreviewResizeGeometry.frame(startingWindowFrame: start, previewRect: canvas,
                viewportSize: size, edges: [.right, .top], translation: CGPoint(x: 20, y: 20),
                minimumSize: minimum)
            XCTAssertGreaterThan(result.width, start.width)
            XCTAssertGreaterThan(result.height, start.height)
            let shrunk = PreviewResizeGeometry.frame(startingWindowFrame: start, previewRect: canvas,
                viewportSize: size, edges: [.right, .top], translation: CGPoint(x: -2000, y: -2000),
                minimumSize: minimum)
            XCTAssertTrue(abs(shrunk.width - minimum.width) < 0.001
                          || abs(shrunk.height - minimum.height) < 0.001)
        }
    }

    func testPhoneHandleScalesTheBackgroundCanvasWhileKeepingItsOppositeEdgeAnchored() {
        let start = CGRect(x: 150, y: 80, width: 1000, height: 700)
        let canvas = CGRect(x: 20, y: 100, width: 960, height: 540)
        let phone = CGRect(x: 365, y: 140, width: 270, height: 460)
        let result = PreviewResizeGeometry.frame(startingWindowFrame: start, previewRect: canvas,
            handleRect: phone, edges: .right, translation: CGPoint(x: 54, y: 0), minimumSize: minimum)
        assertRect(result, CGRect(x: 81, y: 26, width: 1192, height: 808))

        let scale: CGFloat = 1.2
        let resizedPhone = CGRect(x: canvas.minX + (phone.minX - canvas.minX) * scale,
                                  y: canvas.minY + (phone.minY - canvas.minY) * scale,
                                  width: phone.width * scale, height: phone.height * scale)
        XCTAssertEqual(result.minX + resizedPhone.minX, start.minX + phone.minX, accuracy: 0.0001)
        XCTAssertEqual(result.minY + resizedPhone.midY, start.minY + phone.midY, accuracy: 0.0001)
        XCTAssertEqual(result.width - canvas.width * scale, start.width - canvas.width, accuracy: 0.0001)
        XCTAssertEqual(result.height - canvas.height * scale, start.height - canvas.height, accuracy: 0.0001)

        let byCanvas = PreviewResizeGeometry.frame(startingWindowFrame: start, previewRect: canvas,
            edges: .right, translation: CGPoint(x: 192, y: 0), minimumSize: minimum)
        XCTAssertEqual(byCanvas.size, result.size)
        XCTAssertEqual(byCanvas.minX, start.minX, accuracy: 0.0001)
    }

    func testHitTestingFindsEdgesAndRoundedCornersWithoutTakingTheInterior() {
        let rect = CGRect(x: 20, y: 30, width: 300, height: 600)
        let cases: [(CGPoint, PreviewResizeEdges)] = [
            (CGPoint(x: 20, y: 330), .left),
            (CGPoint(x: 327, y: 330), .right),
            (CGPoint(x: 170, y: 637), .top),
            (CGPoint(x: 170, y: 23), .bottom),
            (CGPoint(x: 32, y: 42), [.left, .bottom]),
            (CGPoint(x: 308, y: 618), [.right, .top]),
            (CGPoint(x: 12, y: 638), [.left, .top]),
            (CGPoint(x: 170, y: 330), []),
            (CGPoint(x: 45, y: 55), []),
            (CGPoint(x: 329, y: 330), []),
            (CGPoint(x: 170, y: 639), [])
        ]
        for (point, expected) in cases {
            XCTAssertEqual(PreviewResizeGeometry.edges(at: point, around: rect), expected, "\(point)")
        }
    }

    func testCornerHitZoneCanFollowALargeRoundedPhoneArc() {
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 2200)
        XCTAssertEqual(PreviewResizeGeometry.edges(at: CGPoint(x: 45, y: 45), around: rect,
                                                    cornerWidth: 75), [.left, .bottom])
        XCTAssertTrue(PreviewResizeGeometry.edges(at: CGPoint(x: 500, y: 1100), around: rect,
                                                   cornerWidth: 75).isEmpty)
    }

    func testInvalidGeometryAndConflictingEdgesLeaveTheWindowUnchanged() {
        assertRect(resize([], by: CGPoint(x: 90, y: 90)), window)
        assertRect(resize([.left, .right], by: CGPoint(x: 90, y: 90)), window)
        assertRect(resize([.top, .bottom], by: CGPoint(x: 90, y: 90)), window)
        assertRect(resize(.right, by: CGPoint(x: CGFloat.nan, y: 0)), window)
        let invalid = PreviewResizeGeometry.frame(startingWindowFrame: window, previewRect: .zero,
            edges: .right, translation: CGPoint(x: 90, y: 0), minimumSize: minimum)
        assertRect(invalid, window)
        let outsideHandle = PreviewResizeGeometry.frame(startingWindowFrame: window, previewRect: preview,
            handleRect: CGRect(x: 0, y: 0, width: 800, height: 800), edges: .right,
            translation: CGPoint(x: 90, y: 0), minimumSize: minimum)
        assertRect(outsideHandle, window)
        XCTAssertTrue(PreviewResizeGeometry.edges(at: .zero, around: .zero).isEmpty)
        XCTAssertTrue(PreviewResizeGeometry.edges(at: CGPoint(x: CGFloat.infinity, y: 0), around: preview).isEmpty)
    }

    func testSubpixelContainmentRoundingDoesNotDisableDragging() {
        let roundedHandle = CGRect(x: preview.minX, y: preview.minY,
                                   width: preview.width + 0.0001, height: preview.height + 0.0001)
        let result = PreviewResizeGeometry.frame(startingWindowFrame: window, previewRect: preview,
            handleRect: roundedHandle, edges: .right, translation: CGPoint(x: 90, y: 0), minimumSize: minimum)
        XCTAssertGreaterThan(result.width, window.width)
        XCTAssertEqual(result.width, 590, accuracy: 0.001)

        let roundedCanvas = CGRect(x: 0, y: 0, width: window.width + 0.0001, height: window.height + 0.0001)
        let fullWindowResult = PreviewResizeGeometry.frame(startingWindowFrame: window, previewRect: roundedCanvas,
            edges: .right, translation: CGPoint(x: 90, y: 0), minimumSize: minimum)
        XCTAssertGreaterThan(fullWindowResult.width, window.width)
    }

    private func resize(_ edges: PreviewResizeEdges, by translation: CGPoint) -> CGRect {
        PreviewResizeGeometry.frame(startingWindowFrame: window, previewRect: preview, edges: edges,
                                    translation: translation, minimumSize: minimum)
    }

    private func resizedPreview(in result: CGRect) -> CGRect {
        let whitespace = CGSize(width: window.width - preview.width, height: window.height - preview.height)
        let scale = min((result.width - whitespace.width) / preview.width,
                        (result.height - whitespace.height) / preview.height)
        let size = CGSize(width: preview.width * scale, height: preview.height * scale)
        return CGRect(x: preview.minX + (result.width - whitespace.width - size.width) / 2,
                      y: preview.minY + (result.height - whitespace.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func assertRect(_ actual: CGRect, _ expected: CGRect,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.0001, file: file, line: line)
    }
}
