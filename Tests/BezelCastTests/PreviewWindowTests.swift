import AppKit
import SwiftUI
import XCTest
@testable import BezelCast

@MainActor
final class PreviewWindowTests: XCTestCase {
    func testDeviceAndBezelChangesPreserveTheUserChosenWindowFrame() async throws {
        _ = NSApplication.shared
        let suite = "PreviewWindowTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let capture = DeviceCapture(preferences: preferences, startCapture: false)
        let window = PreviewWindow(capture: capture, windowAccess: WindowAccess())
        defer { window.close() }

        window.setFrame(CGRect(x: 80, y: 90, width: 480, height: 760), display: false)
        let chosenFrame = window.frame
        for id in ["iphone-17-pro/silver", "iphone-13-mini/midnight", "iphone-18-pro-max/black"] {
            capture.selectBezel(id)
            try await waitUntil { capture.customFrameName == BezelLibrary.option(id: id)?.name }
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.frame, chosenFrame, id)
        }

        capture.selectBezel("none")
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertNil(capture.customFrame)
        XCTAssertEqual(window.frame, chosenFrame)

        // A user resize becomes the new viewport even when the feed then
        // changes device family or rotates.
        window.setFrame(CGRect(x: 120, y: 150, width: 700, height: 600), display: false)
        let resizedFrame = window.frame
        capture.handleFrameSize(CGSize(width: 2064, height: 2752))
        try await waitUntil { capture.profile.family == .iPad && capture.customFrame != nil }
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.frame, resizedFrame)

        capture.handleFrameSize(CGSize(width: 2752, height: 2064))
        try await waitUntil { capture.profile.isLandscape }
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.frame, resizedFrame)
    }

    func testHostedPreviewRemainsCenteredAndFitsWhenSwitchingAndResizing() async throws {
        _ = NSApplication.shared
        let suite = "PreviewViewTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let capture = DeviceCapture(preferences: preferences, startCapture: false)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 724),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: PreviewUnderTest(capture: capture))
        host.sizingOptions = []
        window.contentView = host

        for id in ["iphone-13-mini/midnight", "iphone-18-pro-max/black", "ipad-pro-13/silver"] {
            capture.selectBezel(id)
            try await waitUntil { capture.customFrameName == BezelLibrary.option(id: id)?.name }
            for viewport in [CGSize(width: 500, height: 724), CGSize(width: 800, height: 500)] {
                window.setContentSize(viewport)
                let canvas = try XCTUnwrap(capture.customFrame).geometry.frameSize
                try await waitUntil {
                    host.layoutSubtreeIfNeeded()
                    guard let preview = self.previewView(in: host) else { return false }
                    let rect = preview.convert(preview.bounds, to: host)
                    return abs(rect.midX - host.bounds.midX) < 1
                        && abs(rect.midY - host.bounds.midY) < 1
                        && rect.height > 0
                        && abs(rect.width / rect.height - canvas.width / canvas.height) < 0.002
                }
                let preview = try XCTUnwrap(previewView(in: host))
                let rect = preview.convert(preview.bounds, to: host)
                XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(rect), id)
                XCTAssertTrue(abs(rect.width - viewport.width) < 1
                              || abs(rect.height - viewport.height) < 1, id)
            }
        }
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
        XCTAssertTrue(condition(), "Preview update timed out")
    }
}

private struct PreviewUnderTest: View {
    @ObservedObject var capture: DeviceCapture

    var body: some View {
        BezelView(profile: capture.profile, customFrame: capture.customFrame,
                  previewFrames: capture.previewFrames)
    }
}
