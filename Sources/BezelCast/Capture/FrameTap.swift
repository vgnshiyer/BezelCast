@preconcurrency import AVFoundation
import CoreVideo

final class FrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    private var recorder: BezelRecorder?
    private var hasFiredFirstFrame = false
    private var firstFrameCallback: (@Sendable (CGSize) -> Void)?

    var latest: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    func setRecorder(_ recorder: BezelRecorder?) {
        lock.lock(); defer { lock.unlock() }
        self.recorder = recorder
    }

    func setOnFirstFrame(_ callback: (@Sendable (CGSize) -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        firstFrameCallback = callback
        hasFiredFirstFrame = false
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
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer))

        lock.lock()
        buffer = pixelBuffer
        let recorder = self.recorder
        var firstCB: (@Sendable (CGSize) -> Void)?
        if !hasFiredFirstFrame, let cb = firstFrameCallback {
            hasFiredFirstFrame = true
            firstCB = cb
            firstFrameCallback = nil
        }
        lock.unlock()

        recorder?.receive(buffer: pixelBuffer, presentationTime: pts)
        firstCB?(size)
    }
}
