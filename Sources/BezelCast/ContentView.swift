import SwiftUI

struct ContentView: View {
    @ObservedObject var capture: DeviceCapture

    var body: some View {
        ZStack {
            Color.clear

            if let session = capture.session {
                BezelView(session: session, profile: capture.profile, customFrame: capture.customFrame)
                    .padding(.top, 64)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            } else {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(capture.status)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            }

            VStack {
                FloatingControlBar(capture: capture)
                    .padding(.top, 12)
                Spacer()
            }

            if let error = capture.customFrameError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                        .padding(.bottom, 16)
                }
            }
        }
    }
}

private struct FloatingControlBar: View {
    @ObservedObject var capture: DeviceCapture

    var body: some View {
        HStack(spacing: 10) {
            TrafficLights()
                .frame(width: 64, height: 16)
                .padding(.leading, 4)

            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .font(.system(size: 13, weight: .medium))
                Text(deviceShortName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(capture.session == nil ? 0.4 : 1.0))

            Spacer(minLength: 12)

            iconButton(icon: "camera", action: capture.saveScreenshot)
            recordButton
            divider
            iconButton(
                icon: capture.customFrame == nil ? "photo.badge.arrow.down" : "photo.fill",
                action: capture.uploadFrame
            )
            if capture.customFrame != nil {
                iconButton(icon: "xmark.circle.fill", action: capture.clearCustomFrame)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.black.opacity(0.82))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var deviceShortName: String {
        capture.session == nil
            ? "Bezel Cast"
            : capture.profile.displayName
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 18)
    }

    private func iconButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(capture.session == nil)
        .opacity(capture.session == nil ? 0.4 : 1.0)
    }

    private var recordButton: some View {
        Button {
            if capture.isRecording {
                capture.stopRecording()
            } else {
                capture.startRecording()
            }
        } label: {
            Image(systemName: capture.isRecording ? "stop.fill" : "record.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(capture.isRecording ? .red : .white)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(capture.session == nil)
        .opacity(capture.session == nil ? 0.4 : 1.0)
    }
}
