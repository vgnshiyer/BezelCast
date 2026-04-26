@preconcurrency import AVFoundation
import CoreVideo
import Foundation

final class FrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    private var recorder: BezelRecorder?
    private var lastTimestamp: TimeInterval = 0

    var latest: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    var lastFrameTimestamp: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return lastTimestamp
    }

    func setRecorder(_ recorder: BezelRecorder?) {
        lock.lock(); defer { lock.unlock() }
        self.recorder = recorder
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        buffer = nil
        lastTimestamp = 0
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        lock.lock()
        buffer = pixelBuffer
        lastTimestamp = ProcessInfo.processInfo.systemUptime
        let recorder = self.recorder
        lock.unlock()

        recorder?.receive(buffer: pixelBuffer, presentationTime: pts)
    }
}
