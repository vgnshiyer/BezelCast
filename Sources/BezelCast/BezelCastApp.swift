import SwiftUI

@main
struct BezelCastApp: App {
    var body: some Scene {
        WindowGroup("Bezel Cast") {
            ContentView()
                .frame(minWidth: 320, minHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}
