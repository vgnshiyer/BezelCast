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
                subtitle
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

    /// Subtitle view — live-ticking timer when recording, otherwise a static label.
    @ViewBuilder
    private var subtitle: some View {
        if let start = capture.recordingStartTime, capture.isRecording {
            TimelineView(.periodic(from: start, by: 0.5)) { context in
                Text("Recording — \(formatDuration(context.date.timeIntervalSince(start)))")
            }
        } else {
            Text(staticSubtitle)
        }
    }

    private var staticSubtitle: String {
        guard capture.session != nil else { return "Plug in an iPhone via USB" }
        if let name = capture.customFrameName { return name }
        return capture.profile.displayName
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(capture.isRecording ? .red : .white)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(capture.session == nil)
        .opacity(capture.session == nil ? 0.4 : 1.0)
    }
}
