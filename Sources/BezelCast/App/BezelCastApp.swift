import SwiftUI
import AppKit

@main
@MainActor
enum BezelCastApp {
    static func main() {
        // AppDelegate owns the single window. An empty SwiftUI Settings scene
        // adds another window lifecycle even though we have no settings UI.
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let capture = DeviceCapture()
    let windowAccess = WindowAccess()
    private var window: NSWindow?
    /// Token for the local mouse-moved monitor that swaps in the resize
    /// cursor near the window edges. Held so the closure stays alive.
    private var resizeCursorMonitor: Any?
    /// Tracks whether the cursor was last set to a resize cursor by us, so we
    /// only reset to .arrow on the transition back into the interior — that
    /// way SwiftUI keeps owning the cursor everywhere else.
    private var cursorIsResizeCursor = false
    /// Width of the edge zone where the resize cursor appears.
    private let resizeEdgeThickness: CGFloat = 6

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A SwiftPM executable launched from Terminal has no app bundle and
        // can inherit .prohibited. Explicitly opt into a foreground GUI app.
        NSApp.setActivationPolicy(.regular)
        ApplicationMenu.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = PreviewWindow(capture: capture, windowAccess: windowAccess)
        window.center()
        window.setFrameAutosaveName("BezelCastMainWindow")

        window.makeKeyAndOrderFront(nil)
        self.window = window
        installResizeCursorMonitor()
        NSApp.activate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        sender.activate()
        return true
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
}
