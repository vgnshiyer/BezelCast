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
        capture.didApplyPreviewConfiguration = { [weak self] configuration in
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
        let targetSize = CGSize(width: max(currentSize.width, requiredSize.width),
                                height: max(currentSize.height, requiredSize.height))
        guard abs(currentSize.width - targetSize.width) > 8
            || abs(currentSize.height - targetSize.height) > 8 else { return }

        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let currentFrame = window.frame
        let topLeft = CGPoint(x: currentFrame.minX, y: currentFrame.maxY)
        let size = constrained(targetSize, to: visibleFrame)
        let nextFrame = CGRect(x: topLeft.x,
                               y: topLeft.y - size.height,
                               width: size.width,
                               height: size.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            window.setFrame(nextFrame, display: true, animate: animated)
        }
        window.setFrameTopLeftPoint(topLeft)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func constrained(_ size: CGSize, to visibleFrame: CGRect) -> CGSize {
        CGSize(width: min(size.width, visibleFrame.width),
               height: min(size.height, visibleFrame.height))
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
