import SwiftUI
import AppKit

@main
struct BezelCastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No WindowGroup — AppDelegate builds the window manually so it can
        // configure the chromeless transparent style and pre-size it before
        // it ever appears on screen.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let capture = DeviceCapture()
    let windowAccess = WindowAccess()
    private var window: NSWindow?
    private var lastWindowLayoutKey: WindowLayoutKey?
    /// Token for the local mouse-moved monitor that swaps in the resize
    /// cursor near the window edges. Held so the closure stays alive.
    private var resizeCursorMonitor: Any?
    /// Tracks whether the cursor was last set to a resize cursor by us, so we
    /// only reset to .arrow on the transition back into the interior — that
    /// way SwiftUI keeps owning the cursor everywhere else.
    private var cursorIsResizeCursor = false
    /// Width of the edge zone where the resize cursor appears.
    private let resizeEdgeThickness: CGFloat = 6

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = ContentView(capture: capture)
            .environmentObject(windowAccess)
            .frame(minWidth: 360, minHeight: 360)

        // .titled (not .borderless) so AppKit gives us the standard edge-hover
        // resize cursors and drag-to-resize behavior. The title bar is hidden
        // visually; the SwiftUI floating pill still owns the top of the window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 820),
            styleMask: [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentMinSize = NSSize(width: 360, height: 360)
        window.contentView = NSHostingView(rootView: content)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        window.center()
        window.setFrameAutosaveName("BezelCastMainWindow")

        windowAccess.window = window
        window.makeKeyAndOrderFront(nil)
        self.window = window
        installResizeCursorMonitor()
        capture.willApplyPreviewConfiguration = { [weak self] configuration in
            self?.resizeWindowIfLayoutChanged(for: configuration, animated: false)
        }
        resizeWindowIfLayoutChanged(for: capture.previewConfiguration, animated: false)
    }

    /// Hooks into the app's local event stream to swap in the system resize
    /// cursor whenever the pointer is within `resizeEdgeThickness` of an
    /// edge. Cursor rects and tracking areas didn't fire on this transparent
    /// titled-but-chromeless window — SwiftUI's hosting view eats subview
    /// cursor rects, and the OS's normal frame-edge tracking only kicks in
    /// when there's an opaque frame outside the content view. The event
    /// monitor sits above all of that.
    private func installResizeCursorMonitor() {
        resizeCursorMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateResizeCursor(for: event)
            return event
        }
    }

    private func updateResizeCursor(for event: NSEvent) {
        guard let window, event.window === window,
              let contentView = window.contentView else { return }
        let bounds = contentView.bounds
        let location = event.locationInWindow
        let t = resizeEdgeThickness

        // locationInWindow has y growing upward, so y near 0 is the bottom
        // edge and y near bounds.height is the top edge.
        let nearLeft = location.x >= 0 && location.x <= t
        let nearRight = location.x >= bounds.width - t && location.x <= bounds.width
        let nearTop = location.y >= bounds.height - t && location.y <= bounds.height
        let nearBottom = location.y >= 0 && location.y <= t

        if (nearLeft || nearRight) && !nearTop && !nearBottom {
            NSCursor.resizeLeftRight.set()
            cursorIsResizeCursor = true
        } else if (nearTop || nearBottom) && !nearLeft && !nearRight {
            NSCursor.resizeUpDown.set()
            cursorIsResizeCursor = true
        } else if cursorIsResizeCursor {
            // Only restore once on the way out so SwiftUI's hover effects
            // (pointing-hand on buttons, etc.) keep working.
            NSCursor.arrow.set()
            cursorIsResizeCursor = false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func resizeWindowIfLayoutChanged(for configuration: PreviewConfiguration,
                                             animated: Bool) {
        let nextKey = WindowLayoutKey(configuration: configuration)
        guard nextKey != lastWindowLayoutKey else { return }
        lastWindowLayoutKey = nextKey
        resizeWindow(for: configuration, animated: animated)
    }

    private func resizeWindow(for configuration: PreviewConfiguration, animated: Bool) {
        guard let window else { return }
        let requiredSize = DeviceDisplayLayout.windowSize(for: configuration.profile,
                                                          customFrame: configuration.customFrame)
        let currentSize = window.frame.size
        guard abs(currentSize.width - requiredSize.width) > 8
            || abs(currentSize.height - requiredSize.height) > 8 else { return }

        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let currentFrame = window.frame
        let topCenter = CGPoint(x: currentFrame.midX, y: currentFrame.maxY)
        let size = constrained(requiredSize, to: visibleFrame)
        var nextFrame = CGRect(x: topCenter.x - size.width / 2,
                               y: topCenter.y - size.height,
                               width: size.width,
                               height: size.height)
        nextFrame = constrained(nextFrame, to: visibleFrame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            window.setFrame(nextFrame, display: true, animate: animated)
        }
        window.contentView?.layoutSubtreeIfNeeded()
        // setFrame returns synchronously but the CGS frame change otherwise
        // lands a tick later — long enough for SwiftUI to commit the new
        // larger preview into the still-small window and get clipped.
        CATransaction.flush()
    }

    private func constrained(_ size: CGSize, to visibleFrame: CGRect) -> CGSize {
        CGSize(width: min(size.width, visibleFrame.width),
               height: min(size.height, visibleFrame.height))
    }

    private func constrained(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var next = frame
        next.origin.x = min(max(next.minX, visibleFrame.minX), visibleFrame.maxX - next.width)
        next.origin.y = min(max(next.minY, visibleFrame.minY), visibleFrame.maxY - next.height)
        return next
    }
}

private struct WindowLayoutKey: Equatable {
    let windowSize: CGSize

    init(configuration: PreviewConfiguration) {
        windowSize = DeviceDisplayLayout.windowSize(for: configuration.profile,
                                                    customFrame: configuration.customFrame)
    }
}
