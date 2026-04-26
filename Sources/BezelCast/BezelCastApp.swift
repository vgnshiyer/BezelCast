import SwiftUI

@main
struct BezelCastApp: App {
    @StateObject private var capture = DeviceCapture()

    var body: some Scene {
        WindowGroup("Bezel Cast") {
            ContentView(capture: capture)
                .frame(minWidth: 360, minHeight: 720)
        }
        .defaultSize(width: 420, height: 820)
        .windowResizability(.contentSize)
    }
}
