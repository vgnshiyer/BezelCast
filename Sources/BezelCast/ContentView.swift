import SwiftUI

struct ContentView: View {
    @ObservedObject var capture: DeviceCapture

    var body: some View {
        ZStack {
            Color(white: 0.93).ignoresSafeArea()
            if let session = capture.session {
                BezelView(session: session, profile: capture.profile, customFrame: capture.customFrame)
                    .padding(24)
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(capture.status)
                        .foregroundStyle(Color(white: 0.2))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            if let error = capture.customFrameError {
                VStack {
                    Spacer()
                    Text(error)
                        .padding(8)
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                        .padding(.bottom, 12)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    capture.uploadFrame()
                } label: {
                    Label(capture.customFrame == nil ? "Upload Bezel" : "Replace Bezel",
                          systemImage: "photo.badge.arrow.down")
                }
                .disabled(capture.session == nil)
            }
            if capture.customFrame != nil {
                ToolbarItem {
                    Button {
                        capture.clearCustomFrame()
                    } label: {
                        Label("Clear Bezel", systemImage: "xmark.circle")
                    }
                }
            }
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
    }
}
