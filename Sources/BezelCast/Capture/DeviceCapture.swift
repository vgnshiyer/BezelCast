@preconcurrency import AVFoundation
import CoreMediaIO
import CoreImage
import Metal
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
    @Published private(set) var autoDetectedProfile: DeviceProfile?
    @Published private(set) var deviceName: String?
    @Published private(set) var customFrame: NSImage?
    @Published private(set) var customFrameName: String?

    private var customFrameCI: CIImage?

    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private let frameTap = FrameTap()
    private let videoOutput: AVCaptureVideoDataOutput = {
        let output = AVCaptureVideoDataOutput()
        // Let the device deliver its native uncompressed pixel format. Forcing
        // BGRA here moves conversion and bandwidth into AVCapture's delivery
        // graph, which is the part we must keep responsive for the preview.
        output.alwaysDiscardsLateVideoFrames = true
        return output
    }()
    private let videoQueue = DispatchQueue(label: "BezelCast.video", qos: .userInitiated)
    private let renderer: BezelRenderer = {
        // Explicitly Metal-backed so compositing runs on the GPU. The
        // no-arg CIContext() can fall back to software in some configs and
        // that's where bezel-on rendering blows past the 16ms frame budget.
        // cacheIntermediates is FALSE because every captured frame is unique —
        // caching wastes GPU memory and slows things down (per WWDC20 #10008).
        let options: [CIContextOption: Any] = [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            return BezelRenderer(ciContext: CIContext(mtlDevice: device, options: options))
        }
        return BezelRenderer(ciContext: CIContext(options: options))
    }()
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

        // Briefly enable the data output so the first copied frame can identify
        // the connected phone. Normal preview stays single-output; screenshot
        // and recording turn the tap on only while they need frames.
        frameTap.setOnFirstFrame { [weak self] size in
            Task { @MainActor in
                guard let self else { return }
                let detected = DeviceProfile.detect(for: size) ?? DeviceProfile.generic(for: size)
                self.autoDetectedProfile = detected
                if detected != self.profile {
                    self.profile = detected
                    self.clearCustomFrame()
                }
                self.stopVideoOutputIfIdle()
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
        autoDetectedProfile = nil
        clearCustomFrame()
        status = "Disconnected. Plug in an iPhone."
    }

    /// User-driven profile override from the picker. Custom-uploaded bezels
    /// are cleared because they were validated against the previous profile's
    /// frameSize and won't match the new one.
    func selectProfile(_ newProfile: DeviceProfile) {
        guard newProfile != profile else { return }
        clearCustomFrame()
        profile = newProfile
    }

    private func startVideoOutput() {
        videoOutput.connection(with: .video)?.isEnabled = true
    }

    private func stopVideoOutput() {
        videoOutput.connection(with: .video)?.isEnabled = false
        _ = frameTap.cancelNextFrame()
    }

    private func stopVideoOutputIfIdle() {
        if !isRecording {
            stopVideoOutput()
        }
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

        let renderer = self.renderer
        let profile = self.profile
        let customFrameCI = self.customFrameCI

        frameTap.setOnNextFrame { [weak self] buffer in
            Task { @MainActor in
                self?.stopVideoOutputIfIdle()
            }
            Task.detached(priority: .userInitiated) {
                let image = renderer.screenshot(from: buffer, profile: profile, customFrame: customFrameCI)
                guard let image else { return }
                await MainActor.run {
                    writePNGImage(image, to: url)
                }
            }
        }
        startVideoOutput()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if frameTap.cancelNextFrame() {
                stopVideoOutputIfIdle()
            }
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

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}

@MainActor
private func writePNGImage(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}
