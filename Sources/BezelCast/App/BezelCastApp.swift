import SwiftUI
import AppKit

@main
struct BezelCastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No WindowGroup — AppDelegate creates the window manually so we
        // can use a custom NSWindow subclass without object_setClass hacks
        // (those break SwiftUI's KVO observers on the window).
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let capture = DeviceCapture()
    let windowAccess = WindowAccess()
    private var window: NSWindow?
    private var lastWindowLayoutKey: WindowLayoutKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = ContentView(capture: capture)
            .environmentObject(windowAccess)
            .frame(minWidth: 360, minHeight: 360)

        let window = KeyableBorderlessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 820),
            styleMask: [.borderless, .resizable, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: content)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.center()
        window.setFrameAutosaveName("BezelCastMainWindow")

        windowAccess.window = window
        window.makeKeyAndOrderFront(nil)
        self.window = window
        capture.willApplyPreviewConfiguration = { [weak self] configuration in
            self?.resizeWindowIfLayoutChanged(for: configuration, animated: false)
        }
        resizeWindowIfLayoutChanged(for: capture.previewConfiguration, animated: false)
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

/// .borderless windows reject key/main status by default, breaking keyboard
/// shortcuts and `NSApp.keyWindow` access. Override both to true.
final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct WindowLayoutKey: Equatable {
    let windowSize: CGSize

    init(configuration: PreviewConfiguration) {
        windowSize = DeviceDisplayLayout.windowSize(for: configuration.profile,
                                                    customFrame: configuration.customFrame)
    }
}
