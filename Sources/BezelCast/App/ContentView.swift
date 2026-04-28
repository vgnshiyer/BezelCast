import SwiftUI

struct ContentView: View {
    @ObservedObject var capture: DeviceCapture

    var body: some View {
        ZStack {
            Color.clear

            if let session = capture.session {
                BezelView(session: session, profile: capture.profile, customFrame: capture.customFrame)
                    // Toolbar pill sits at y=12 with ~52px height = 64px from
                    // the top. Add a consistent 16px breathing gap on all four
                    // sides — top stacks on top of the toolbar offset.
                    .padding(.top, 80)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
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
    @State private var showingProfilePicker = false

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

            captureGroup
            profilePicker
            ellipsisIcon
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
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

    /// Picker for the bezel profile. SwiftUI's Menu with .borderlessButton
    /// menuStyle silently drops every label child after the first, so we
    /// roll our own with Button + popover — that way the iPhone glyph and
    /// chevron both render reliably. Aspect-incompatible profiles are
    /// filtered out so a 16:9 SE feed never lands in a 19.5:9 Pro bezel.
    private var profilePicker: some View {
        Button {
            showingProfilePicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .font(.system(size: 18, weight: .regular))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .regular))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        .disabled(capture.session == nil)
        .opacity(capture.session == nil ? 0.4 : 1.0)
        .popover(isPresented: $showingProfilePicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(compatibleProfiles, id: \.id) { p in
                    Button {
                        capture.selectProfile(p)
                        showingProfilePicker = false
                    } label: {
                        HStack {
                            Text(p.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if p.id == capture.profile.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            .frame(width: 240)
        }
    }

    private var compatibleProfiles: [DeviceProfile] {
        guard let auto = capture.autoDetectedProfile else { return DeviceProfile.catalog }
        return DeviceProfile.compatible(with: auto)
    }

    /// Overflow menu — currently just the bezel toggle. Single-Image labels
    /// don't trigger the borderlessButton-drops-children bug we hit on the
    /// profile picker, so the native Menu is fine here.
    private var ellipsisIcon: some View {
        Menu {
            Button(capture.customFrame == nil ? "Add Bezel..." : "Remove Bezel") {
                if capture.customFrame == nil {
                    capture.uploadFrame()
                } else {
                    capture.clearCustomFrame()
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(capture.session == nil)
        .opacity(capture.session == nil ? 0.4 : 1.0)
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
