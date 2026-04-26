import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var capture: DeviceCapture
    @State private var keyMonitor: Any?

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
                .tint(capture.isRecording ? .red : nil)
                .disabled(capture.session == nil)
            }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains([.command, .shift]),
                  capture.session != nil else { return event }
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            switch key {
            case "s":
                MainActor.assumeIsolated { capture.saveScreenshot() }
                return nil
            case "r":
                MainActor.assumeIsolated {
                    if capture.isRecording { capture.stopRecording() }
                    else { capture.startRecording() }
                }
                return nil
            default:
                return event
            }
        }
    }
}
