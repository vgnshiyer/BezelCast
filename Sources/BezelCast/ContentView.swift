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
                VStack(spacing: 14) {
                    Image(systemName: "iphone")
                        .font(.system(size: 80, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(capture.status)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
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

            VStack(alignment: .leading, spacing: 1) {
                Text(titleLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitleLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(1)
            .opacity(capture.session == nil ? 0.55 : 1.0)

            Spacer(minLength: 12)

            iconButton(icon: "camera", action: capture.saveScreenshot)
            recordButton
            bezelGroup
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    private var titleLine: String {
        guard capture.session != nil else { return "Bezel Cast" }
        return capture.deviceName ?? capture.profile.displayName
    }

    private var subtitleLine: String {
        guard capture.session != nil else { return "Plug in an iPhone via USB" }
        if capture.isRecording { return "Recording" }
        if let name = capture.customFrameName { return name }
        return capture.profile.displayName
    }

    /// Bezel upload + clear, grouped inside their own subtle pill — they're
    /// two halves of one feature (manage custom bezel).
    private var bezelGroup: some View {
        HStack(spacing: 0) {
            iconButton(icon: "iphone", action: capture.uploadFrame)
            if capture.customFrame != nil {
                iconButton(icon: "xmark.circle.fill", action: capture.clearCustomFrame)
            }
        }
        .padding(.horizontal, 3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
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
