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
    }
}
