@preconcurrency import AVFoundation
import CoreVideo
import Foundation

final class FrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    private var recorder: BezelRecorder?
    private var lastFrameTime: TimeInterval = 0
    private var lastChangeTime: TimeInterval = 0
    private var lastFingerprint: UInt64 = 0

    var latest: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    var lastFrameTimestamp: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return lastFrameTime
    }

    var lastContentChangeTimestamp: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return lastChangeTime
    }

    func setRecorder(_ recorder: BezelRecorder?) {
        lock.lock(); defer { lock.unlock() }
        self.recorder = recorder
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        buffer = nil
        lastFrameTime = 0
        lastChangeTime = 0
        lastFingerprint = 0
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let now = ProcessInfo.processInfo.systemUptime
        let fingerprint = sampleFingerprint(pixelBuffer)

        lock.lock()
        buffer = pixelBuffer
        lastFrameTime = now
        if fingerprint != lastFingerprint {
            lastChangeTime = now
            lastFingerprint = fingerprint
        }
        let recorder = self.recorder
        lock.unlock()

        recorder?.receive(buffer: pixelBuffer, presentationTime: pts)
    }

    private func sampleFingerprint(_ pixelBuffer: CVPixelBuffer) -> UInt64 {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // 4×4 grid of pixel samples spread across the frame, FNV-1a hashed.
        var hash: UInt64 = 14695981039346656037
        for row in 0..<4 {
            for col in 0..<4 {
                let x = (width * (col + 1)) / 5
                let y = (height * (row + 1)) / 5
                let offset = y * bytesPerRow + x * 4
                let pixel = base.load(fromByteOffset: offset, as: UInt32.self)
                hash ^= UInt64(pixel)
                hash = hash &* 1099511628211
            }
        }
        return hash
    }
}
