@preconcurrency import AVFoundation
import CoreMediaIO
import CoreImage
import AppKit
import Combine

@MainActor
final class DeviceCapture: ObservableObject {
    @Published private(set) var session: AVCaptureSession?
    @Published private(set) var status = "Plug in an iPhone via USB.\nTap Trust if prompted."

    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private let frameTap = FrameTap()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "BezelCast.video", qos: .userInitiated)
    private let ciContext = CIContext()

    init() {
        enableiOSScreenCaptureDevices()

        // A discovery call must happen before AVCaptureDeviceWasConnected fires.
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
    }

    private func detach() {
        session?.stopRunning()
        session = nil
        frameTap.clear()
        status = "Disconnected. Plug in an iPhone."
    }

    func saveScreenshot() {
        guard let buffer = frameTap.latest,
              let image = renderBezeled(from: buffer) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "BezelCast-\(timestamp()).png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        writePNG(image, to: url)
    }

    private func renderBezeled(from buffer: CVPixelBuffer) -> NSImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let videoSize = ciImage.extent.size
        guard videoSize.width > 0, videoSize.height > 0 else { return nil }

        let frameThickness = videoSize.width * 0.026
        let outerWidth = videoSize.width + 2 * frameThickness
        let outerHeight = videoSize.height + 2 * frameThickness
        let outerCorner = outerWidth * 0.16
        let innerCorner = max(outerCorner - frameThickness, 0)
        let islandWidth = outerWidth * 0.32
        let islandHeight = outerWidth * 0.096
        let islandTopOffset = frameThickness + outerWidth * 0.025

        guard let cgVideo = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let outerSize = NSSize(width: outerWidth, height: outerHeight)
        let image = NSImage(size: outerSize)
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: outerSize),
                           cornerWidth: outerCorner, cornerHeight: outerCorner, transform: nil))
        ctx.fillPath()

        let innerRect = CGRect(x: frameThickness, y: frameThickness,
                               width: videoSize.width, height: videoSize.height)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: innerRect, cornerWidth: innerCorner, cornerHeight: innerCorner, transform: nil))
        ctx.clip()
        ctx.draw(cgVideo, in: innerRect)
        ctx.restoreGState()

        let islandRect = CGRect(x: (outerWidth - islandWidth) / 2,
                                y: outerHeight - islandTopOffset - islandHeight,
                                width: islandWidth, height: islandHeight)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(CGPath(roundedRect: islandRect,
                           cornerWidth: islandHeight / 2, cornerHeight: islandHeight / 2, transform: nil))
        ctx.fillPath()

        return image
    }

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
