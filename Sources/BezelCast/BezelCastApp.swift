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
        .commands {
            CommandMenu("Capture") {
                Button("Take Screenshot") {
                    capture.saveScreenshot()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(capture.session == nil)

                Button(capture.isRecording ? "Stop Recording" : "Start Recording") {
                    if capture.isRecording {
                        capture.stopRecording()
                    } else {
                        capture.startRecording()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(capture.session == nil)
            }
        }
    }
}
