import AppKit
import SwiftUI

/// Holds a weak reference to our app's NSWindow so SwiftUI views can call
/// performClose / performMiniaturize / performZoom directly. The standard
/// title-bar buttons are hidden in favor of a custom SwiftUI traffic-light
/// pill, so the buttons in that pill need a direct handle to the window.
final class WindowAccess: ObservableObject {
    weak var window: NSWindow?
}
