import SwiftUI

@main
struct BezelCastApp: App {
    var body: some Scene {
        WindowGroup("Bezel Cast") {
            ContentView()
                .frame(minWidth: 360, minHeight: 720)
        }
        .defaultSize(width: 420, height: 820)
        .windowResizability(.contentSize)
    }
}
