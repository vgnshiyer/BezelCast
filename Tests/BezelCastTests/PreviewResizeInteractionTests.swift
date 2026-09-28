import AppKit
import SwiftUI
import XCTest
@testable import BezelCast

@MainActor
final class PreviewResizeInteractionTests: XCTestCase {
    func testCornerDraggingResizesHostedPhoneAndRepeatedDragsAccumulate() async throws {
        try await withPreview { capture, window, host in
            let canvas = try XCTUnwrap(capture.customFrame).geometry.frameSize
            var previousWindow = window.frame
            var previousPreview = try previewRect(in: host)

            for _ in 0..<2 {
                let overlay = try XCTUnwrap(resizeView(in: host))
                let device = overlay.deviceRectInView
                try drag(overlay, in: window,
                         from: CGPoint(x: device.maxX, y: device.minY),
                         by: CGSize(width: 14, height: -24))
                try await waitUntil {
                    host.layoutSubtreeIfNeeded()
                    guard let preview = self.previewView(in: host) else { return false }
                    let rect = preview.convert(preview.bounds, to: host)
                    return rect.height > previousPreview.height + 0.5
                }

                let resizedPreview = try previewRect(in: host)
                XCTAssertGreaterThan(window.frame.width, previousWindow.width)
                XCTAssertGreaterThan(window.frame.height, previousWindow.height)
                XCTAssertGreaterThan(resizedPreview.width, previousPreview.width)
                XCTAssertGreaterThan(resizedPreview.height, previousPreview.height)
                XCTAssertEqual(resizedPreview.width / resizedPreview.height,
                               canvas.width / canvas.height, accuracy: 0.002)
                XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(resizedPreview))
                previousWindow = window.frame
                previousPreview = resizedPreview
            }
        }
    }

    func testResizeOverlayOnlyInterceptsEdgesAndLeavesCenterForMoving() async throws {
        try await withPreview { _, _, host in
            let overlay = try XCTUnwrap(resizeView(in: host))
            let device = overlay.deviceRectInView
            let parent = try XCTUnwrap(overlay.superview)
            @MainActor func hit(_ localPoint: CGPoint) -> NSView? {
                overlay.hitTest(overlay.convert(localPoint, to: parent))
            }

            XCTAssertNil(hit(CGPoint(x: device.midX, y: device.midY)))
            XCTAssertTrue(hit(CGPoint(x: device.maxX, y: device.midY)) === overlay)
            XCTAssertTrue(hit(CGPoint(x: device.minX, y: device.minY)) === overlay)
            XCTAssertTrue(hit(CGPoint(x: device.midX, y: device.maxY)) === overlay)
            XCTAssertNil(hit(CGPoint(x: overlay.bounds.minX - 20, y: overlay.bounds.midY)))
            XCTAssertFalse(overlay.mouseDownCanMoveWindow)

            let edgeAtRoot = overlay.convert(CGPoint(x: device.maxX, y: device.midY), to: host.superview)
            XCTAssertTrue(host.hitTest(edgeAtRoot) === overlay,
                          "The real SwiftUI hierarchy must route phone-edge events to the resize view")
            let centerAtRoot = overlay.convert(CGPoint(x: device.midX, y: device.midY), to: host.superview)
            XCTAssertFalse(host.hitTest(centerAtRoot) === overlay,
                           "The phone interior must remain available for normal window dragging")
        }
    }

    func testDraggingPhoneEdgeInsideBackgroundResizesTheWholeCanvas() async throws {
        try await withPreview(background: "gradient:ocean") { capture, window, host in
            let overlay = try XCTUnwrap(resizeView(in: host))
            let initialDevice = overlay.deviceRectInView
            let initialCanvas = overlay.canvasRect
            let initialPreview = try previewRect(in: host)
            let initialWindow = window.frame
            XCTAssertLessThan(initialDevice.width, initialCanvas.width * 0.75,
                              "The phone edge must be inside the background, away from the window edge")

            try drag(overlay, in: window,
                     from: CGPoint(x: initialDevice.maxX, y: initialDevice.midY),
                     by: CGSize(width: 14, height: 0))
            try await waitUntil {
                host.layoutSubtreeIfNeeded()
                guard let preview = self.previewView(in: host) else { return false }
                return preview.convert(preview.bounds, to: host).width > initialPreview.width + 0.5
            }

            let resizedPreview = try previewRect(in: host)
            let resizedOverlay = try XCTUnwrap(resizeView(in: host))
            XCTAssertGreaterThan(window.frame.width, initialWindow.width)
            XCTAssertGreaterThan(window.frame.height, initialWindow.height)
            XCTAssertGreaterThan(resizedOverlay.deviceRectInView.width, initialDevice.width)
            XCTAssertGreaterThan(resizedOverlay.canvasRect.width, initialCanvas.width)
            XCTAssertEqual(resizedPreview.width / resizedPreview.height, 16.0 / 9.0, accuracy: 0.002)
            XCTAssertEqual(resizedOverlay.deviceRectInView.width / resizedOverlay.canvasRect.width,
                           initialDevice.width / initialCanvas.width, accuracy: 0.002)
            XCTAssertEqual(capture.backgrounds.selectedID, "gradient:ocean")
            XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(resizedPreview))
        }
    }

    func testDraggingPastMinimumClampsWindowAndPreviewKeepsItsAspect() async throws {
        try await withPreview { capture, window, host in
            let overlay = try XCTUnwrap(resizeView(in: host))
            let device = overlay.deviceRectInView
            let initialFrame = window.frame
            let initialPreview = try previewRect(in: host)
            let minimumFrame = window.frameRect(forContentRect: CGRect(origin: .zero,
                                                                       size: window.contentMinSize)).size
            try drag(overlay, in: window,
                     from: CGPoint(x: device.maxX, y: device.minY),
                     by: CGSize(width: -2_000, height: 2_000))
            try await waitUntil {
                host.layoutSubtreeIfNeeded()
                guard let preview = self.previewView(in: host) else { return false }
                let rect = preview.convert(preview.bounds, to: host)
                return window.frame.width < initialFrame.width && window.frame.height < initialFrame.height
                    && rect.height < initialPreview.height
            }

            XCTAssertGreaterThanOrEqual(window.frame.width, minimumFrame.width - 0.5)
            XCTAssertGreaterThanOrEqual(window.frame.height, minimumFrame.height - 0.5)
            XCTAssertTrue(abs(window.frame.width - minimumFrame.width) < 1
                          || abs(window.frame.height - minimumFrame.height) < 1,
                          "Shrinking past the limit should stop at a minimum dimension")
            let canvas = try XCTUnwrap(capture.customFrame).geometry.frameSize
            let rect = try previewRect(in: host)
            XCTAssertEqual(rect.width / rect.height, canvas.width / canvas.height, accuracy: 0.002)
            XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(rect))
        }
    }

    func testLandscapeIPadCanResizeFromTheBackgroundCanvasBorder() async throws {
        try await withPreview(background: "gradient:dusk") { capture, window, host in
            capture.selectBezel("ipad-pro-13/silver")
            try await waitUntil { capture.customFrameName == "iPad Pro 13-inch (M4/M5) · Silver" }
            capture.handleFrameSize(CGSize(width: 2752, height: 2064))
            capture.backgrounds.setCanvas(.square)
            try await waitUntil {
                host.layoutSubtreeIfNeeded()
                guard let overlay = self.resizeView(in: host) else { return false }
                return capture.profile.family == .iPad && capture.profile.isLandscape
                    && abs(overlay.canvasRect.width - overlay.canvasRect.height) < 0.5
                    && overlay.deviceRectInView.width > overlay.deviceRectInView.height
            }

            let overlay = try XCTUnwrap(resizeView(in: host))
            let initialCanvas = overlay.canvasRect
            let initialDevice = overlay.deviceRectInView
            let initialWindow = window.frame
            let initialPreview = try previewRect(in: host)
            let top = CGPoint(x: initialCanvas.midX, y: initialCanvas.maxY)
            XCTAssertGreaterThan(top.y - initialDevice.maxY, PreviewResizeView.edgeInset)
            XCTAssertTrue(host.hitTest(overlay.convert(top, to: host.superview)) === overlay)

            try drag(overlay, in: window, from: top, by: CGSize(width: 0, height: 20))
            try await waitUntil {
                host.layoutSubtreeIfNeeded()
                guard let preview = self.previewView(in: host) else { return false }
                return preview.convert(preview.bounds, to: host).height > initialPreview.height + 0.5
            }

            let resizedPreview = try previewRect(in: host)
            let resizedOverlay = try XCTUnwrap(resizeView(in: host))
            XCTAssertGreaterThan(window.frame.width, initialWindow.width)
            XCTAssertGreaterThan(window.frame.height, initialWindow.height)
            XCTAssertEqual(resizedPreview.width / resizedPreview.height, 1, accuracy: 0.002)
            XCTAssertEqual(resizedOverlay.deviceRectInView.width / resizedOverlay.deviceRectInView.height,
                           initialDevice.width / initialDevice.height, accuracy: 0.002)
            XCTAssertGreaterThan(resizedOverlay.deviceRectInView.width, initialDevice.width)
            XCTAssertEqual(capture.backgrounds.selectedID, "gradient:dusk")
            XCTAssertTrue(capture.profile.isLandscape)
        }
    }

    private func drag(_ overlay: PreviewResizeView, in window: NSWindow,
                      from start: CGPoint, by delta: CGSize) throws {
        let startInWindow = overlay.convert(start, to: nil)
        let startOnScreen = window.convertPoint(toScreen: startInWindow)
        let endOnScreen = CGPoint(x: startOnScreen.x + delta.width, y: startOnScreen.y + delta.height)
        overlay.mouseDown(with: try mouseEvent(.leftMouseDown, window: window, screenPoint: startOnScreen))
        overlay.mouseDragged(with: try mouseEvent(.leftMouseDragged, window: window, screenPoint: endOnScreen))
        // Resize may move the window origin; resolve the release location again.
        overlay.mouseUp(with: try mouseEvent(.leftMouseUp, window: window, screenPoint: endOnScreen))
    }

    private func mouseEvent(_ type: NSEvent.EventType, window: NSWindow, screenPoint: CGPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type,
                                         location: window.convertPoint(fromScreen: screenPoint),
                                         modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         eventNumber: 0, clickCount: 1,
                                         pressure: type == .leftMouseUp ? 0 : 1))
    }

    private func withPreview(background: String = "none",
                             _ body: (DeviceCapture, NSWindow, NSHostingView<ResizePreviewUnderTest>) async throws -> Void) async throws {
        _ = NSApplication.shared
        let suite = "PreviewResizeInteractionTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let capture = DeviceCapture(preferences: preferences, startCapture: false)
        try await waitUntil { capture.customFrame != nil }
        capture.backgrounds.select(background)
        capture.backgrounds.setCanvas(.landscape)

        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 900)
        let window = NSWindow(contentRect: CGRect(x: visible.midX - 210, y: visible.midY - 230,
                                                  width: 420, height: 460),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.contentMinSize = CGSize(width: 320, height: 360)
        defer { window.close() }
        let host = NSHostingView(rootView: ResizePreviewUnderTest(capture: capture))
        host.sizingOptions = []
        window.contentView = host
        try await waitUntil {
            host.layoutSubtreeIfNeeded()
            guard let overlay = self.resizeView(in: host), let preview = self.previewView(in: host) else { return false }
            return overlay.deviceRectInView.width > 0 && overlay.canvasRect.width > 0 && preview.bounds.height > 0
        }
        try await body(capture, window, host)
    }

    private func previewRect(in host: NSView) throws -> CGRect {
        let preview = try XCTUnwrap(previewView(in: host))
        return preview.convert(preview.bounds, to: host)
    }

    private func resizeView(in view: NSView) -> PreviewResizeView? {
        if let overlay = view as? PreviewResizeView { return overlay }
        return view.subviews.lazy.compactMap { self.resizeView(in: $0) }.first
    }

    private func previewView(in view: NSView) -> LayeredPreviewView? {
        if let preview = view as? LayeredPreviewView { return preview }
        return view.subviews.lazy.compactMap { self.previewView(in: $0) }.first
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "Hosted preview did not finish resizing")
    }
}

private struct ResizePreviewUnderTest: View {
    @ObservedObject var capture: DeviceCapture

    var body: some View {
        let configuration = capture.previewConfiguration
        BezelView(profile: configuration.profile, customFrame: configuration.customFrame,
                  previewFrames: capture.previewFrames, presentation: configuration.presentation)
    }
}
