import AppKit

/// Preserve standard shortcuts when hosting SwiftUI inside our AppKit window.
@MainActor
enum ApplicationMenu {
    static func install() {
        let main = NSMenu()
        let app = submenu("BezelCast", in: main)
        app.addItem(withTitle: "Hide BezelCast", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit BezelCast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Nil targets route editing commands to the focused text field.
        let edit = submenu("Edit", in: main)
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = submenu("Window", in: main)
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    private static func submenu(_ title: String, in main: NSMenu) -> NSMenu {
        let item = NSMenuItem()
        let submenu = NSMenu(title: title)
        item.submenu = submenu
        main.addItem(item)
        return submenu
    }
}
