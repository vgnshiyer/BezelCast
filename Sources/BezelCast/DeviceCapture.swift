@preconcurrency import AVFoundation
import CoreMediaIO
import CoreImage
import AppKit
import Combine

@MainActor
final class DeviceCapture: ObservableObject {
    @Published private(set) var session: AVCaptureSession?
    @Published private(set) var status = "Plug in an iPhone via USB.\nTap Trust if prompted."
    @Published private(set) var isRecording = false
    @Published private(set) var isLive = false

    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private let frameTap = FrameTap()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "BezelCast.video", qos: .userInitiated)
    private let renderer = BezelRenderer(ciContext: CIContext())
    private var recorder: BezelRecorder?
    private var livenessTask: Task<Void, Never>?

    init() {
        enableiOSScreenCaptureDevices()

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

        videoOutput.setSampleBufferDelegate(frameTap, queue: videoQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
        self.session = session
        self.status = device.localizedName
        startLivenessCheck()
    }

    private func detach() {
        if isRecording {
            discardRecording()
        }
        livenessTask?.cancel()
        livenessTask = nil
        isLive = false
        session?.stopRunning()
        session = nil
        frameTap.clear()
        status = "Disconnected. Plug in an iPhone."
    }

    /// Polls the FrameTap to detect when the iPhone stops streaming (e.g. screen lock).
    private func startLivenessCheck() {
        livenessTask?.cancel()
        livenessTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let last = self.frameTap.lastFrameTimestamp
                let live = last > 0 && (now - last) < 0.5
                if self.isLive != live {
                    self.isLive = live
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    // MARK: - Screenshot

    func saveScreenshot() {
        guard let buffer = frameTap.latest,
              let image = renderer.screenshot(from: buffer) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "BezelCast-\(timestamp()).png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writePNG(image, to: url)
    }

    // MARK: - Recording

    func startRecording() {
        guard recorder == nil, session != nil else { return }
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BezelCast-\(UUID().uuidString).mov")
        let recorder = BezelRecorder(url: tempURL, renderer: renderer)
        self.recorder = recorder
        frameTap.setRecorder(recorder)
        isRecording = true
    }

    func stopRecording() {
        guard let recorder else { return }
        isRecording = false
        frameTap.setRecorder(nil)
        self.recorder = nil

        recorder.stop { [weak self] tempURL in
            DispatchQueue.main.async {
                self?.promptToSaveRecording(tempURL: tempURL)
            }
        }
    }

    private func discardRecording() {
        guard let recorder else { return }
        isRecording = false
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
