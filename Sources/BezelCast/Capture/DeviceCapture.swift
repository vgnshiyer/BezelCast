@preconcurrency import AVFoundation
import CoreMediaIO
import CoreImage
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class DeviceCapture: ObservableObject {
    @Published private(set) var session: AVCaptureSession?
    @Published private(set) var status = "Plug in an iPhone via USB.\nTap Trust if prompted."
    @Published private(set) var isRecording = false
    @Published private(set) var recordingStartTime: Date?
    @Published private(set) var profile: DeviceProfile = DeviceProfile.catalog.first!
    @Published private(set) var deviceName: String?
    @Published private(set) var customFrame: NSImage?
    @Published private(set) var customFrameName: String?

    private var customFrameCI: CIImage?

    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private let frameTap = FrameTap()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "BezelCast.video", qos: .userInitiated)
    private let renderer = BezelRenderer(ciContext: CIContext())
    private var recorder: BezelRecorder?

    init() {
        enableiOSScreenCaptureDevices()
        videoOutput.setSampleBufferDelegate(frameTap, queue: videoQueue)

        let warmup = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified)

        connectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main
        ) { [weak self] note in
            guard let device = note.object as? AVCaptureDevice,
                  device.hasMediaType(.muxed) else { return }
            Task { @MainActor in self?.attach(device: device) }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.detach() }
        }

        if let device = warmup.devices.first {
            attach(device: device)
        }
    }

    private func enableiOSScreenCaptureDevices() {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &prop, 0, nil, UInt32(MemoryLayout.size(ofValue: allow)), &allow)
    }

    private func attach(device: AVCaptureDevice) {
        let session = AVCaptureSession()
        session.beginConfiguration()
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            status = "Couldn't attach \(device.localizedName)"
            return
        }
        session.addInput(input)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()

        // The iPhone presents as a muxed device, so CMVideoFormatDescriptionGetDimensions
        // typically returns 0×0 from device.activeFormat. Try it as a hint, but fall back
        // to first-frame detection (below) for the real dimensions.
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let hintedSize = CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
        if hintedSize.width > 0, hintedSize.height > 0 {
            profile = DeviceProfile.detect(for: hintedSize) ?? DeviceProfile.generic(for: hintedSize)
        }
        // Don't overwrite profile with garbage — keep the catalog default until first frame.
        clearCustomFrame()

        // Enable the data output briefly so a frame can arrive for detection.
        // The first-frame callback refines the profile and disables the connection
        // again, so the steady-state preview path stays single-output.
        frameTap.setOnFirstFrame { [weak self] size in
            Task { @MainActor in
                guard let self else { return }
                let detected = DeviceProfile.detect(for: size) ?? DeviceProfile.generic(for: size)
                if detected != self.profile {
                    self.profile = detected
                    self.clearCustomFrame()
                }
                self.videoOutput.connection(with: .video)?.isEnabled = false
            }
        }
        videoOutput.connection(with: .video)?.isEnabled = true

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
        self.session = session
        self.deviceName = device.localizedName
    }

    private func detach() {
        if isRecording {
            discardRecording()
        }
        stopVideoOutput()
        session?.stopRunning()
        session = nil
        deviceName = nil
        clearCustomFrame()
        status = "Disconnected. Plug in an iPhone."
    }

    private func startVideoOutput() {
        videoOutput.connection(with: .video)?.isEnabled = true
    }

    private func stopVideoOutput() {
        videoOutput.connection(with: .video)?.isEnabled = false
        frameTap.clear()
    }

    // MARK: - Custom frame upload

    /// Error message from the most recent uploadFrame attempt, if it failed
    /// (wrong dimensions, unreadable file). nil otherwise.
    @Published private(set) var customFrameError: String?

    func uploadFrame() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Upload Bezel"
        panel.message = "Pick a PNG sized \(Int(profile.frameSize.width))×\(Int(profile.frameSize.height)) for \(profile.displayName)."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadCustomFrame(from: url)
    }

    func clearCustomFrame() {
        customFrame = nil
        customFrameCI = nil
        customFrameName = nil
        customFrameError = nil
    }

    private func loadCustomFrame(from url: URL) {
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            customFrameError = "Couldn't read \(url.lastPathComponent)."
            return
        }
        let pxSize = CGSize(width: cgImage.width, height: cgImage.height)
        let expected = profile.frameSize
        guard abs(pxSize.width - expected.width) < 1, abs(pxSize.height - expected.height) < 1 else {
            customFrameError = "Image is \(Int(pxSize.width))×\(Int(pxSize.height)). \(profile.displayName) needs \(Int(expected.width))×\(Int(expected.height))."
            return
        }
        customFrame = nsImage
        customFrameCI = CIImage(cgImage: cgImage)
        customFrameName = url.deletingPathExtension().lastPathComponent
        customFrameError = nil
    }

    // MARK: - Screenshot

    func saveScreenshot() {
        guard session != nil else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "BezelCast-\(timestamp()).png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        frameTap.clear()
        startVideoOutput()

        Task { @MainActor in
            defer { stopVideoOutput() }
            let start = Date()
            while frameTap.latest == nil && Date().timeIntervalSince(start) < 1.0 {
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            guard let buffer = frameTap.latest,
                  let image = renderer.screenshot(from: buffer, profile: profile, customFrame: customFrameCI) else { return }
            writePNG(image, to: url)
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard recorder == nil, session != nil else { return }
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BezelCast-\(UUID().uuidString).mov")
        let recorder = BezelRecorder(url: tempURL, renderer: renderer, profile: profile, customFrame: customFrameCI)
        self.recorder = recorder
        frameTap.setRecorder(recorder)
        startVideoOutput()
        recordingStartTime = Date()
        isRecording = true
    }

    func stopRecording() {
        guard let recorder else { return }
        isRecording = false
        recordingStartTime = nil
        frameTap.setRecorder(nil)
        self.recorder = nil
        stopVideoOutput()

        recorder.stop { [weak self] tempURL in
            DispatchQueue.main.async {
                self?.promptToSaveRecording(tempURL: tempURL)
            }
        }
    }

    private func discardRecording() {
        guard let recorder else { return }
        isRecording = false
        recordingStartTime = nil
        frameTap.setRecorder(nil)
        self.recorder = nil
        stopVideoOutput()
        recorder.stop { tempURL in
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        }
    }

    private func promptToSaveRecording(tempURL: URL?) {
        guard let tempURL else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.nameFieldStringValue = "BezelCast-\(timestamp()).mov"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            } catch {
                print("Failed to move recording: \(error)")
            }
        } else {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // MARK: - Helpers

    private func writePNG(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}
