import AppKit
import CoreImage
import CoreVideo
import SwiftUI
import XCTest
@testable import BezelCast

@MainActor
final class BackgroundPreviewTests: XCTestCase {
    func testBackgroundCanvasFitsInsideTheUnchangedPreviewWindow() async throws {
        _ = NSApplication.shared
        let suite = "BackgroundPreviewTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let capture = DeviceCapture(preferences: preferences, startCapture: false)
        let window = PreviewWindow(capture: capture, windowAccess: WindowAccess())
        defer { window.close() }
        let host = NSHostingView(rootView: PresentedPreviewUnderTest(capture: capture))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(CGSize(width: 700, height: 700))
        let windowFrame = window.frame
        capture.backgrounds.select("gradient:ocean")
        for canvas in BackgroundCanvas.allCases {
            capture.backgrounds.setCanvas(canvas)
            try await Task.sleep(nanoseconds: 30_000_000)
            host.layoutSubtreeIfNeeded()
            let preview = try XCTUnwrap(previewView(in: host))
            let rect = preview.convert(preview.bounds, to: host)
            XCTAssertEqual(window.frame, windowFrame)
            XCTAssertEqual(rect.width / rect.height, canvas.size.width / canvas.size.height, accuracy: 0.002)
            XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(rect))
            XCTAssertEqual(rect.midX, host.safeAreaRect.midX, accuracy: 1)
            XCTAssertEqual(rect.midY, host.safeAreaRect.midY, accuracy: 1)
            XCTAssertEqual(preview.layer?.shadowOpacity, 0)
        }
    }

    func testBackgroundPickerFitsAndRenderExamples() async throws {
        _ = NSApplication.shared
        let suite = "BackgroundPickerTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = BackgroundStore(preferences: preferences)
        store.select("gradient:ocean")
        let host = NSHostingView(rootView: BackgroundPicker(store: store, isRecording: false, importImage: {})
            .background(Color(red: 0.13, green: 0.13, blue: 0.14)))
        let size = host.fittingSize
        XCTAssertEqual(size.width, 390, accuracy: 1)
        XCTAssertLessThan(size.height, 700)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        defer { window.close() }
        try await Task.sleep(nanoseconds: 300_000_000)
        host.layoutSubtreeIfNeeded()

        // Opt-in artifacts let UI and actual export pixels be inspected without
        // capturing the user's desktop or requiring a connected phone.
        guard let path = ProcessInfo.processInfo.environment["BEZELCAST_TEST_ARTIFACTS"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("background-picker.png"))

        let option = try XCTUnwrap(BezelLibrary.option(id: "iphone-18-pro/silver"))
        let profile = option.profile
        let frame = try XCTUnwrap(BezelLibrary.frame(for: option, orientedTo: profile))
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, Int(profile.screenSize.width), Int(profile.screenSize.height),
                                          kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let input = try XCTUnwrap(buffer)
        let context = CIContext()
        let screen = try XCTUnwrap(CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0, y: profile.screenSize.height),
            "inputColor0": CIColor(red: 0.05, green: 0.1, blue: 0.2),
            "inputColor1": CIColor(red: 0.2, green: 0.4, blue: 0.65)
        ])?.outputImage).cropped(to: CGRect(origin: .zero, size: profile.screenSize))
        context.render(screen, to: input)
        let wallpaper = BackgroundLibrary.wallpapers().first { $0.name == "Sonoma" }
        for canvas in [BackgroundCanvas.landscape, .portrait] {
            let background = try wallpaper.map { try BackgroundLibrary.load($0) } ?? store.background
            let image = try XCTUnwrap(BezelRenderer(ciContext: context).screenshot(from: input, profile: profile,
                customFrame: frame.renderFrame, presentation: CapturePresentation(background: background, canvas: canvas)))
            let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("background-\(canvas.rawValue).png"))
        }
    }

    private func previewView(in view: NSView) -> LayeredPreviewView? {
        if let result = view as? LayeredPreviewView { return result }
        return view.subviews.lazy.compactMap { self.previewView(in: $0) }.first
    }
}

private struct PresentedPreviewUnderTest: View {
    @ObservedObject var capture: DeviceCapture
    var body: some View {
        let configuration = capture.previewConfiguration
        BezelView(profile: configuration.profile, customFrame: configuration.customFrame,
                  previewFrames: capture.previewFrames, presentation: configuration.presentation)
    }
}
