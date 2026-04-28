@preconcurrency import AVFoundation
import CoreMediaIO
import CoreImage
import Metal
import AppKit
import Combine
import UniformTypeIdentifiers

struct PreviewConfiguration: Sendable {
    let profile: DeviceProfile
    let customFrame: CustomFrame?
}

@MainActor
final class DeviceCapture: ObservableObject {
    @Published private(set) var session: AVCaptureSession?
    @Published private(set) var status = "Plug in a device.\nTap Trust if prompted."
    @Published private(set) var isRecording = false
    @Published private(set) var recordingStartTime: Date?
    @Published private(set) var previewConfiguration = PreviewConfiguration(
        profile: DeviceProfile.catalog.first!,
        customFrame: nil
    )
    @Published private(set) var autoDetectedProfile: DeviceProfile?
    @Published private(set) var deviceName: String?
    @Published private(set) var customFrameName: String?
    let previewFrames = PreviewFrameStore()

    var profile: DeviceProfile { previewConfiguration.profile }
    var customFrame: CustomFrame? { previewConfiguration.customFrame }

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
    private lazy var previewCompositor = PreviewCompositor(renderer: renderer,
                                                           frameStore: previewFrames)
    var willApplyPreviewConfiguration: ((PreviewConfiguration) -> Void)?

    init() {
        enableiOSScreenCaptureDevices()
        videoOutput.setSampleBufferDelegate(frameTap, queue: videoQueue)
        frameTap.setOnFrameSizeChange { [weak self] size in
            Task { @MainActor in
                self?.handleFrameSize(size)
            }
        }

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

    deinit {
        customFrameErrorDismissTask?.cancel()
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
        }
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
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

        // iOS/iPadOS devices present as muxed devices, so
        // CMVideoFormatDescriptionGetDimensions typically returns 0×0 from
        // device.activeFormat. Try it as a hint, but fall back to first-frame
        // detection (below) for the real dimensions.
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let hintedSize = CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
        if hintedSize.width > 0,
           hintedSize.height > 0,
           let hintedProfile = DeviceProfile.detect(for: hintedSize) {
            applyPreview(profile: hintedProfile, customFrame: nil)
        }
        // Don't overwrite profile with garbage — keep the catalog default until first frame.
        clearCustomFrame()

        // Keep the data output enabled for lightweight size observation. The
        // delegate does not copy frames unless screenshot/recording needs one,
        // so this catches rotation immediately without reviving the BYOB freeze
        // path.
        frameTap.resetFrameSize()
        videoOutput.connection(with: .video)?.isEnabled = true

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
        self.session = session
        self.deviceName = device.localizedName
    }

    private func rejectUnsupportedDevice(named name: String, capturedSize: CGSize) {
        if isRecording {
            discardRecording()
        }
        stopVideoOutput()
        session?.stopRunning()
        session = nil
        deviceName = nil
        autoDetectedProfile = nil
        clearCustomFrame()
        status = "Unsupported device: \(name)\nBezelCast supports known iPhone and iPad screen sizes.\nCaptured size: \(Int(capturedSize.width))×\(Int(capturedSize.height))"
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
        status = "Disconnected. Plug in a device."
    }

    private func applyPreview(profile: DeviceProfile, customFrame: CustomFrame?) {
        let shouldClearPreview = (self.customFrame == nil) != (customFrame == nil)
        let configuration = PreviewConfiguration(profile: profile, customFrame: customFrame)
        willApplyPreviewConfiguration?(configuration)
        previewCompositor.setConfiguration(configuration)
        let compositor = previewCompositor
        frameTap.setPreviewSink { buffer, pts, completion in
            compositor.receive(buffer: buffer,
                               presentationTime: pts,
                               completion: completion)
        }
        if shouldClearPreview {
            previewFrames.display(nil)
        }
        previewConfiguration = configuration
    }

    private func handleFrameSize(_ size: CGSize) {
        guard let detected = DeviceProfile.detect(for: size) else {
            rejectUnsupportedDevice(named: deviceName ?? "Device", capturedSize: size)
            return
        }

        let hadDetectedProfile = autoDetectedProfile != nil
        let selectedProfile = profile
        autoDetectedProfile = detected

        let nextProfile: DeviceProfile
        if hadDetectedProfile,
           selectedProfile.family == detected.family,
           abs(selectedProfile.aspectRatio - detected.aspectRatio) < 0.05 {
            nextProfile = selectedProfile.oriented(matching: size)
        } else {
            nextProfile = detected
        }

        guard nextProfile != profile else { return }
        let previousID = profile.id
        let nextCustomFrame: CustomFrame?
        if let frame = customFrame {
            if previousID == nextProfile.id, let orientedFrame = frame.oriented(to: nextProfile) {
                nextCustomFrame = orientedFrame
            } else {
                nextCustomFrame = nil
                customFrameName = nil
                setCustomFrameError(nil)
            }
        } else {
            nextCustomFrame = nil
        }
        applyPreview(profile: nextProfile, customFrame: nextCustomFrame)
    }

    /// User-driven profile override from the picker. Custom-uploaded bezels
    /// are cleared because their cutout geometry was validated against the
    /// previous profile and may not match the new one.
    func selectProfile(_ newProfile: DeviceProfile) {
        guard newProfile != profile else { return }
        customFrameName = nil
        setCustomFrameError(nil)
        applyPreview(profile: newProfile, customFrame: nil)
    }

    private func startVideoOutput() {
        videoOutput.connection(with: .video)?.isEnabled = true
    }

    private func stopVideoOutput() {
        videoOutput.connection(with: .video)?.isEnabled = false
        _ = frameTap.cancelNextFrame()
    }

    private func cancelPendingFrameRequest() {
        _ = frameTap.cancelNextFrame()
    }

    // MARK: - Custom frame upload

    /// Error message from the most recent uploadFrame attempt, if it failed
    /// (wrong dimensions, unreadable file). nil otherwise.
    @Published private(set) var customFrameError: String?
    private var customFrameErrorDismissTask: Task<Void, Never>?

    func uploadFrame() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Upload Bezel"
        panel.message = uploadPanelMessage

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadCustomFrame(from: url)
    }

    func clearCustomFrame() {
        applyPreview(profile: profile, customFrame: nil)
        customFrameName = nil
        setCustomFrameError(nil)
    }

    private var uploadPanelMessage: String {
        if profile.hasPresetFrameGeometry {
            let size = profile.frameSize
            return "Pick a PNG sized \(Int(size.width))×\(Int(size.height)) or \(Int(size.height))×\(Int(size.width)) for \(profile.displayName)."
        }
        return "Pick a bezel PNG with a transparent screen cutout matching \(profile.displayName)'s display aspect."
    }

    private func setCustomFrameError(_ message: String?) {
        customFrameErrorDismissTask?.cancel()
        customFrameErrorDismissTask = nil
        customFrameError = message

        guard let message else { return }
        customFrameErrorDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, self?.customFrameError == message else { return }
            self?.customFrameError = nil
            self?.customFrameErrorDismissTask = nil
        }
    }

    private func loadCustomFrame(from url: URL) {
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            setCustomFrameError("Couldn't read \(url.lastPathComponent).")
            return
        }

        let pxSize = CGSize(width: cgImage.width, height: cgImage.height)
        let geometry: FrameGeometry
        if profile.hasPresetFrameGeometry {
            let expected = profile.frameSize
            if pxSize.matches(expected) {
                geometry = profile.defaultFrameGeometry
            } else if pxSize.matches(expected.swapped) {
                geometry = profile.defaultFrameGeometry.rotated(clockwise: !profile.isLandscape)
            } else {
                setCustomFrameError("Image is \(Int(pxSize.width))×\(Int(pxSize.height)). \(profile.displayName) needs \(Int(expected.width))×\(Int(expected.height)) or \(Int(expected.height))×\(Int(expected.width)).")
                return
            }
        } else {
            guard let screenRect = CustomFrameDetector.screenRect(in: cgImage) else {
                setCustomFrameError("Couldn't find a transparent screen cutout in \(url.lastPathComponent).")
                return
            }
            guard screenRect.hasAspect(of: profile.screenSize) else {
                setCustomFrameError("Cutout is \(Int(screenRect.width))×\(Int(screenRect.height)). \(profile.displayName) needs a \(Int(profile.screenSize.width))×\(Int(profile.screenSize.height)) aspect.")
                return
            }
            geometry = FrameGeometry(frameSize: pxSize, screenRect: screenRect)
        }

        let name = url.deletingPathExtension().lastPathComponent
        guard let customFrame = CustomFrame.make(name: name,
                                                 image: nsImage,
                                                 cgImage: cgImage,
                                                 geometry: geometry,
                                                 profile: profile) else {
            setCustomFrameError("\(url.lastPathComponent) doesn't match \(profile.displayName)'s current orientation.")
            return
        }
        applyPreview(profile: profile, customFrame: customFrame)
        customFrameName = name
        setCustomFrameError(nil)
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
        let customFrame = self.customFrame

        frameTap.setOnNextFrame { [weak self] buffer in
            Task { @MainActor in
                self?.cancelPendingFrameRequest()
            }
            Task.detached(priority: .userInitiated) {
                let currentSize = CGSize(width: CVPixelBufferGetWidth(buffer),
                                         height: CVPixelBufferGetHeight(buffer))
                let currentProfile = profile.oriented(matching: currentSize)
                let currentFrame = customFrame?.oriented(to: currentProfile)?.renderFrame
                let image = renderer.screenshot(from: buffer,
                                                profile: currentProfile,
                                                customFrame: currentFrame)
                guard let image else { return }
                await MainActor.run {
                    writePNGImage(image, to: url)
                }
            }
        }
        startVideoOutput()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            cancelPendingFrameRequest()
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard recorder == nil, session != nil else { return }
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BezelCast-\(UUID().uuidString).mov")
        let recorder = BezelRecorder(url: tempURL, renderer: renderer, profile: profile, customFrame: customFrame)
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
        cancelPendingFrameRequest()

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

private extension CGSize {
    var swapped: CGSize { CGSize(width: height, height: width) }

    func matches(_ other: CGSize, tolerance: CGFloat = 1) -> Bool {
        abs(width - other.width) < tolerance && abs(height - other.height) < tolerance
    }
}
