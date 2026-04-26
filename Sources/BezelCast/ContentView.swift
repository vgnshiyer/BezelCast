import SwiftUI

struct ContentView: View {
    @StateObject private var capture = DeviceCapture()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session = capture.session {
                CapturePreview(session: session)
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(capture.status)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}
