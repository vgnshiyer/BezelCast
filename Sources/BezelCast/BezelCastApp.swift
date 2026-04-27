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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = ContentView(capture: capture)
            .environmentObject(windowAccess)
            .frame(minWidth: 360, minHeight: 720)

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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// .borderless windows reject key/main status by default, breaking keyboard
/// shortcuts and `NSApp.keyWindow` access. Override both to true.
final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
