@preconcurrency import AVFoundation
import CoreVideo

final class FrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    private var recorder: BezelRecorder?

    var latest: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    func setRecorder(_ recorder: BezelRecorder?) {
        lock.lock(); defer { lock.unlock() }
        self.recorder = recorder
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        buffer = nil
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        lock.lock()
        buffer = pixelBuffer
        let recorder = self.recorder
        lock.unlock()

        recorder?.receive(buffer: pixelBuffer, presentationTime: pts)
    }
}
