import SwiftUI

struct ContentView: View {
    @StateObject private var capture = DeviceCapture()

    var body: some View {
        ZStack {
            Color(white: 0.93).ignoresSafeArea()
            if let session = capture.session {
                BezelView(session: session)
                    .padding(24)
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(capture.status)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    capture.saveScreenshot()
                } label: {
                    Label("Capture", systemImage: "camera")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(capture.session == nil)
            }
            ToolbarItem {
                Button {
                    if capture.isRecording {
                        capture.stopRecording()
                    } else {
                        capture.startRecording()
                    }
                } label: {
                    Label(capture.isRecording ? "Stop" : "Record",
                          systemImage: capture.isRecording ? "stop.circle.fill" : "record.circle")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(capture.session == nil)
            }
        }
    }
}
