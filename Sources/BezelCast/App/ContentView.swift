import SwiftUI

struct ContentView: View {
    @ObservedObject var capture: DeviceCapture

    var body: some View {
        GeometryReader { geo in
            let toolbarWidth = toolbarWidth(in: geo.size)

            VStack(spacing: 0) {
                FloatingControlBar(capture: capture)
                    .frame(width: toolbarWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, PreviewLayout.toolbarTop)
                    .frame(height: PreviewLayout.toolbarHeight + PreviewLayout.toolbarTop,
                           alignment: .top)
                    .zIndex(1)

                content
                    .padding(.top, PreviewLayout.toolbarGap)
                    .padding(.horizontal, PreviewLayout.sidePadding)
                    .padding(.bottom, PreviewLayout.sidePadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.clear)
            .transaction { transaction in
                transaction.animation = nil
            }
            .overlay(alignment: .bottom) {
                if let error = capture.customFrameError {
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

    @ViewBuilder
    private var content: some View {
        if capture.session != nil {
            let configuration = capture.previewConfiguration
            BezelView(profile: configuration.profile,
                      customFrame: configuration.customFrame,
                      previewFrames: capture.previewFrames)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func toolbarWidth(in containerSize: CGSize) -> CGFloat {
        let availableWidth = max(0, containerSize.width - PreviewLayout.sidePadding * 2)
        guard capture.session != nil else { return availableWidth }

        let configuration = capture.previewConfiguration
        let previewSize = DeviceDisplayLayout.previewSize(for: configuration.profile,
                                                          customFrame: configuration.customFrame)
        let availableHeight = max(0,
                                  containerSize.height
                                      - PreviewLayout.toolbarTop
                                      - PreviewLayout.toolbarHeight
                                      - PreviewLayout.toolbarGap
                                      - PreviewLayout.sidePadding)
        let fit = min(1,
                      availableWidth / previewSize.width,
                      availableHeight / previewSize.height)
        let displayWidth = previewSize.width * fit
        return min(availableWidth, max(PreviewLayout.minimumToolbarWidth, displayWidth))
    }
}

private enum PreviewLayout {
    static let toolbarTop: CGFloat = 12
    static let toolbarHeight: CGFloat = 52
    static let toolbarGap: CGFloat = 16
    static let sidePadding: CGFloat = 16
    static let minimumToolbarWidth: CGFloat = 360
}

private struct FloatingControlBar: View {
    @ObservedObject var capture: DeviceCapture
    @State private var showingBezelPicker = false

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

            HStack(spacing: 6) {
                captureGroup
                bezelButton
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    /// Screenshot + record grouped inside a shared pill — they're both
    /// "capture this frame/clip" actions, so they read as one feature.
    private var captureGroup: some View {
        HStack(spacing: 0) {
            iconButton(icon: "camera", action: capture.saveScreenshot)
            recordButton
        }
        .padding(.horizontal, 3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
    }

    private var titleLine: String {
        guard capture.session != nil else { return "BezelCast" }
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
        guard capture.session != nil else { return "Plug in a device" }
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

    private var bezelButton: some View {
        Button {
            showingBezelPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        .help("Choose bezel and finish")
        .accessibilityLabel("Choose bezel and finish")
        .popover(isPresented: $showingBezelPicker, arrowEdge: .top) {
            BezelPicker(capture: capture) {
                showingBezelPicker = false
                DispatchQueue.main.async { capture.uploadFrame() }
            }
        }
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
            Image(systemName: capture.isRecording ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(capture.isRecording ? .red : .white)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(capture.session == nil)
        .opacity(capture.session == nil ? 0.4 : 1.0)
    }
}
