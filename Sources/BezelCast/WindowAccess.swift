import AppKit
import SwiftUI

/// Holds a weak reference to our app's NSWindow so SwiftUI views can call
/// performClose / performMiniaturize / performZoom directly. With .borderless
/// style, canBecomeKey defaults to false and NSApp.keyWindow is nil, so the
/// usual `NSApp.keyWindow?.performClose(nil)` path is a no-op.
final class WindowAccess: ObservableObject {
    weak var window: NSWindow?
}
