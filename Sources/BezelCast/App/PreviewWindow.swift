import AppKit
import SwiftUI

/// The user owns the window's size; device changes only update its content.
@MainActor
final class PreviewWindow: NSWindow {
    init(capture: DeviceCapture, windowAccess: WindowAccess) {
        // Keep AppKit's native resizing while hiding the title bar in favor
        // of the floating controls inside the transparent window.
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 820),
                   styleMask: [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)

        let content = ContentView(capture: capture)
            .environmentObject(windowAccess)
            .frame(minWidth: 360, minHeight: 360)
        let hostingView = NSHostingView(rootView: content)
        // SwiftUI may enforce the minimum, but a new device must never
        // propose a different ideal or maximum window size.
        hostingView.sizingOptions = [.minSize]

        title = "BezelCast"
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        contentMinSize = NSSize(width: 360, height: 360)
        contentView = hostingView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true
        windowAccess.window = self
    }
}
